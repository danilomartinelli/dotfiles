// herdr-linear is a JSON bridge between the Herdr mod and Linear's GraphQL API.
// The API key comes only from the LINEAR_API_KEY environment variable.
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// ── Request shape and swappable I/O ────────────────────────────────────────

type Obj = map[string]any
type Request struct {
	Action      string   `json:"action"`
	Identifier  string   `json:"identifier"`
	Identifiers []string `json:"identifiers"`
	Issue       string   `json:"issue"`
	Scope       string   `json:"scope"`
	State       string   `json:"state"`
	Team        string   `json:"team"`
	Search      string   `json:"search"`
	Cursor      string   `json:"cursor"`
	Body        string   `json:"body"`
	Parent      string   `json:"parent"`
	StateID     string   `json:"stateId"`
	Assignee    string   `json:"assignee"`
	Unassign    bool     `json:"unassign"`
	Priority    *int     `json:"priority"`
}

const endpoint = "https://api.linear.app/graphql"

var missingKey = errors.New("LINEAR_API_KEY is not set. Export a personal API key from https://linear.app/settings/api in your shell environment, then refresh.")
var identifierPattern = regexp.MustCompile(`^([A-Za-z][A-Za-z0-9]*)-([1-9][0-9]*)$`)

// Swapped in tests.
var transport = httpPost
var readKey = loadKey

// ── Transport and key lookup ──────────────────────────────────────────────

func httpPost(ctx context.Context, key string, payload []byte) (int, []byte, error) {
	req, err := http.NewRequestWithContext(ctx, "POST", endpoint, bytes.NewReader(payload))
	if err != nil {
		return 0, nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", key)
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return 0, nil, fmt.Errorf("Linear is unreachable: %w", err)
	}
	defer res.Body.Close()
	body, err := io.ReadAll(io.LimitReader(res.Body, 8<<20))
	return res.StatusCode, body, err
}

// GUI-launched apps often lack the shell's exports, so ask a login shell too.
func loadKey() (string, error) {
	if key := strings.TrimSpace(os.Getenv("LINEAR_API_KEY")); key != "" {
		return key, nil
	}
	shell := os.Getenv("SHELL")
	if shell == "" {
		shell = "/bin/sh"
	}
	// Startup files may print a greeting or wait for input: take the last line, within a limit.
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, shell, "-lic", `printf '\n%s' "$LINEAR_API_KEY"`).Output()
	if err == nil {
		lines := strings.Split(string(out), "\n")
		if key := strings.TrimSpace(lines[len(lines)-1]); key != "" {
			return key, nil
		}
	}
	return "", missingKey
}

func gql(ctx context.Context, key, query string, vars Obj) (Obj, error) {
	payload, _ := json.Marshal(Obj{"query": query, "variables": vars})
	status, raw, err := transport(ctx, key, payload)
	if err != nil {
		return nil, err
	}
	if status == 401 || status == 403 {
		return nil, errors.New("Linear rejected LINEAR_API_KEY. Export a valid key, then refresh.")
	}
	var res struct {
		Data   Obj `json:"data"`
		Errors []struct {
			Message string `json:"message"`
		} `json:"errors"`
	}
	if err := json.Unmarshal(raw, &res); err != nil {
		return nil, fmt.Errorf("Linear returned an unreadable response (HTTP %d)", status)
	}
	if len(res.Errors) > 0 {
		msg := res.Errors[0].Message
		if strings.Contains(strings.ToLower(msg), "authentication") {
			return nil, errors.New("Linear rejected LINEAR_API_KEY. Export a valid key, then refresh.")
		}
		return nil, fmt.Errorf("Linear: %s", msg)
	}
	if status >= 400 {
		return nil, fmt.Errorf("Linear request failed (HTTP %d)", status)
	}
	return res.Data, nil
}

// ── Small JSON helpers ──────────────────────────────────────────────────

func object(v any) Obj { m, _ := v.(map[string]any); return m }
func array(v any) []any {
	a, _ := v.([]any)
	if a == nil {
		return []any{}
	}
	return a
}
func text(v any) string { s, _ := v.(string); return s }
func nodes(v any) []any { return array(object(v)["nodes"]) }
func cursor(v any) string {
	p := object(object(v)["pageInfo"])
	if p["hasNextPage"] == true {
		return text(p["endCursor"])
	}
	return ""
}
func nullable(s string) any {
	if s == "" {
		return nil
	}
	return s
}

// ── GraphQL selections ──────────────────────────────────────────────────

const pageInfo = `pageInfo{hasNextPage endCursor}`

// Fields for a list row; detailFields adds everything the detail view shows.
const cardFields = `id identifier title url priority priorityLabel createdAt updatedAt branchName state{id name type color} assignee{id name displayName} team{id key name} labels{nodes{id name color}} project{name url} cycle{number name}`
const commentFields = `id body url createdAt updatedAt user{id name displayName} parent{id}`
const detailFields = cardFields + ` description estimate creator{name displayName} parent{identifier title url} children{nodes{id identifier title url updatedAt assignee{name displayName} state{name type color}}} attachments{nodes{id title subtitle url sourceType metadata}} comments(first:100){` + pageInfo + ` nodes{` + commentFields + `}} team{states{nodes{id name type color position}} members{nodes{id name displayName active}}}`

const viewerQuery = `{viewer{id name displayName email} teams{nodes{id key name}}}`

func viewer(ctx context.Context, key string) (Obj, error) {
	data, err := gql(ctx, key, viewerQuery, nil)
	if err != nil {
		return nil, err
	}
	return Obj{"viewer": data["viewer"], "teams": nodes(data["teams"])}, nil
}

// ── Reads: viewer, list, detail ──────────────────────────────────────────

// The panel's state filter maps onto Linear workflow state types.
var stateTypes = map[string][]any{
	"active":    {"triage", "backlog", "unstarted", "started"},
	"backlog":   {"triage", "backlog"},
	"started":   {"started"},
	"done":      {"completed"},
	"cancelled": {"canceled"},
	"all":       nil,
}

func listFilter(r Request) (Obj, error) {
	filter := Obj{}
	switch r.Scope {
	case "mine":
		filter["assignee"] = Obj{"isMe": Obj{"eq": true}}
	case "cycle":
		filter["cycle"] = Obj{"isActive": Obj{"eq": true}}
	case "", "all":
	default:
		return nil, errors.New("invalid scope")
	}
	types, ok := stateTypes[r.State]
	if !ok && r.State != "" {
		return nil, errors.New("invalid state")
	}
	if r.State == "" {
		types = stateTypes["active"]
	}
	if types != nil {
		filter["state"] = Obj{"type": Obj{"in": types}}
	}
	if r.Team != "" {
		filter["team"] = Obj{"key": Obj{"eq": r.Team}}
	}
	if q := strings.TrimSpace(r.Search); q != "" {
		or := []any{
			Obj{"title": Obj{"containsIgnoreCase": q}},
			Obj{"description": Obj{"containsIgnoreCase": q}},
		}
		// A bare number can't be matched as text: it's that number in any team.
		if number, err := strconv.Atoi(strings.TrimPrefix(q, "#")); err == nil && number > 0 {
			or = append(or, Obj{"number": Obj{"eq": number}})
		}
		if m := identifierPattern.FindStringSubmatch(q); m != nil {
			var number int
			fmt.Sscanf(m[2], "%d", &number)
			// Two keys in one `or` entry are OR-ed by Linear; `and` keeps them together.
			or = append(or, Obj{"and": []any{Obj{"team": Obj{"key": Obj{"eqIgnoreCase": m[1]}}}, Obj{"number": Obj{"eq": number}}}})
		}
		filter["or"] = or
	}
	return filter, nil
}

func list(ctx context.Context, key string, r Request) (any, error) {
	filter, err := listFilter(r)
	if err != nil {
		return nil, err
	}
	data, err := gql(ctx, key, `query($filter:IssueFilter,$after:String){issues(filter:$filter,first:50,after:$after,orderBy:updatedAt){`+pageInfo+` nodes{`+cardFields+`}}}`, Obj{"filter": filter, "after": nullable(r.Cursor)})
	if err != nil {
		return nil, err
	}
	return Obj{"items": nodes(data["issues"]), "cursor": cursor(data["issues"])}, nil
}

// An issue by identifier (ENG-123) or by Linear's UUID.
func fetchIssue(ctx context.Context, key, ref string) (Obj, error) {
	var issue Obj
	if m := identifierPattern.FindStringSubmatch(ref); m != nil {
		var number int
		fmt.Sscanf(m[2], "%d", &number)
		data, err := gql(ctx, key, `query($team:String!,$number:Float!){issues(filter:{team:{key:{eqIgnoreCase:$team}},number:{eq:$number}},first:1){nodes{`+detailFields+`}}}`, Obj{"team": m[1], "number": number})
		if err != nil {
			return nil, err
		}
		found := nodes(data["issues"])
		if len(found) == 0 {
			return nil, nil
		}
		issue = object(found[0])
	} else {
		data, err := gql(ctx, key, `query($id:String!){issue(id:$id){`+detailFields+`}}`, Obj{"id": ref})
		if err != nil {
			return nil, err
		}
		issue = object(data["issue"])
		if issue == nil {
			return nil, nil
		}
	}
	comments := nodes(issue["comments"])
	for next := cursor(issue["comments"]); next != ""; {
		data, err := gql(ctx, key, `query($id:String!,$after:String){issue(id:$id){comments(first:100,after:$after){`+pageInfo+` nodes{`+commentFields+`}}}}`, Obj{"id": issue["id"], "after": next})
		if err != nil {
			return nil, err
		}
		conn := object(data["issue"])["comments"]
		comments = append(comments, nodes(conn)...)
		next = cursor(conn)
	}
	issue["comments"] = comments
	issue["children"] = nodes(issue["children"])
	issue["attachments"] = nodes(issue["attachments"])
	issue["labels"] = nodes(issue["labels"])
	team := object(issue["team"])
	if team != nil {
		team["states"] = nodes(team["states"])
		team["members"] = nodes(team["members"])
	}
	return issue, nil
}

// ── Dispatch: one JSON request in, one JSON result out ────────────────────

func handle(ctx context.Context, r Request) (any, error) {
	key, err := readKey()
	if err != nil {
		return nil, err
	}
	switch r.Action {
	case "viewer":
		return viewer(ctx, key)
	case "list":
		return list(ctx, key, r)
	case "detail":
		if r.Identifier == "" {
			return nil, errors.New("identifier required")
		}
		issue, err := fetchIssue(ctx, key, r.Identifier)
		if err != nil {
			return nil, err
		}
		if issue == nil {
			return nil, fmt.Errorf("%s was not found in Linear", r.Identifier)
		}
		return issue, nil
	case "resolve":
		// Candidates from a branch name: unknown identifiers are dropped, not errors.
		found := []any{}
		for _, id := range r.Identifiers {
			if !identifierPattern.MatchString(id) {
				continue
			}
			issue, err := fetchIssue(ctx, key, id)
			if err != nil {
				return nil, err
			}
			if issue != nil {
				found = append(found, issue)
			}
		}
		return Obj{"items": found}, nil
	case "comment":
		if r.Issue == "" || strings.TrimSpace(r.Body) == "" {
			return nil, errors.New("issue ID and body required")
		}
		return gql(ctx, key, `mutation($issue:String!,$body:String!,$parent:String){commentCreate(input:{issueId:$issue,body:$body,parentId:$parent}){success comment{id}}}`, Obj{"issue": r.Issue, "body": r.Body, "parent": nullable(r.Parent)})
	case "update":
		if r.Issue == "" {
			return nil, errors.New("issue ID required")
		}
		input := Obj{}
		if r.StateID != "" {
			input["stateId"] = r.StateID
		}
		if r.Unassign {
			input["assigneeId"] = nil
		} else if r.Assignee != "" {
			input["assigneeId"] = r.Assignee
		}
		if r.Priority != nil {
			if *r.Priority < 0 || *r.Priority > 4 {
				return nil, errors.New("priority must be 0 to 4")
			}
			input["priority"] = *r.Priority
		}
		if len(input) == 0 {
			return nil, errors.New("nothing to update")
		}
		data, err := gql(ctx, key, `mutation($id:String!,$input:IssueUpdateInput!){issueUpdate(id:$id,input:$input){success issue{id state{id name type color} assignee{id name displayName} priority priorityLabel}}}`, Obj{"id": r.Issue, "input": input})
		return data, err
	default:
		return nil, errors.New("unknown action")
	}
}

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: herdr-linear '<JSON request>'")
		os.Exit(1)
	}
	var r Request
	if err := json.Unmarshal([]byte(os.Args[1]), &r); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 26*time.Second)
	defer cancel()
	result, err := handle(ctx, r)
	if err != nil {
		_ = json.NewEncoder(os.Stdout).Encode(Obj{"error": err.Error()})
		os.Exit(1)
	}
	_ = json.NewEncoder(os.Stdout).Encode(result)
}
