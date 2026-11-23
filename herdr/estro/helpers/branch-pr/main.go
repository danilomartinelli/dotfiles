// herdr-pr is a JSON bridge between the Herdr mod and gh's authenticated API.
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

type Obj = map[string]any
type Request struct {
	Branch   string            `json:"branch"`
	Job      int               `json:"job"`
	Action   string            `json:"action"`
	Repo     string            `json:"repo"`
	Tab      string            `json:"tab"`
	State    string            `json:"state"`
	Search   string            `json:"search"`
	Cursors  map[string]string `json:"cursors"`
	Number   int               `json:"number"`
	Run      int               `json:"run"`
	Thread   string            `json:"thread"`
	Body     string            `json:"body"`
	Event    string            `json:"event"`
	ID       string            `json:"id"`
	Method   string            `json:"method"`
	Head     string            `json:"head"`
	Reviewer string            `json:"reviewer"`
	// Preferences from the mod's settings.
	PageSize int               `json:"pageSize"`
	Tail     int               `json:"tail"`
	Tools    map[string]string `json:"tools"`
}

var ghBinary = "gh"

func pageSize(r Request) int {
	if r.PageSize < 1 || r.PageSize > 100 {
		return 25
	}
	return r.PageSize
}

func tailBytes(r Request) int {
	if r.Tail < 1 {
		return 60000
	}
	return r.Tail
}

var segmentPattern = regexp.MustCompile(`^[A-Za-z0-9_.-]+$`)
var runner = runCommand

func runCommand(ctx context.Context, args []string, input []byte) ([]byte, error) {
	cmd := exec.CommandContext(ctx, ghBinary, args...)
	cmd.Stdin = bytes.NewReader(input)
	var out, stderr bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return nil, describeGhError(err, stderr.String())
	}
	return out.Bytes(), nil
}

// Everything here goes through the GitHub CLI, so say plainly when it is absent or logged out.
func describeGhError(err error, stderr string) error {
	stderr = strings.TrimSpace(stderr)
	if errors.Is(err, exec.ErrNotFound) || errors.Is(err, os.ErrNotExist) {
		return errors.New("GitHub CLI (gh) is not installed. Install it from https://cli.github.com, run `gh auth login`, then refresh.")
	}
	if strings.Contains(stderr, "gh auth login") || strings.Contains(stderr, "not logged in") {
		return errors.New("GitHub CLI is not logged in. Run `gh auth login` in a terminal, then refresh.")
	}
	return fmt.Errorf("GitHub: %s (%w)", stderr, err)
}
func gh(ctx context.Context, args ...string) (any, error) {
	b, e := runner(ctx, args, nil)
	if e != nil {
		return nil, e
	}
	var v any
	e = json.Unmarshal(b, &v)
	return v, e
}
func gql(ctx context.Context, query string, vars Obj) (Obj, error) {
	payload := Obj{"query": query, "variables": vars}
	b, _ := json.Marshal(payload)
	raw, e := runner(ctx, []string{"api", "graphql", "--input", "-"}, b)
	if e != nil {
		return nil, e
	}
	var res struct {
		Data   Obj   `json:"data"`
		Errors []Obj `json:"errors"`
	}
	if e = json.Unmarshal(raw, &res); e != nil {
		return nil, e
	}
	if len(res.Errors) > 0 {
		return nil, fmt.Errorf("GitHub: %v", res.Errors)
	}
	return res.Data, nil
}
func object(v any) Obj { m, _ := v.(map[string]any); return m }
func array(v any) []any {
	a, _ := v.([]any)
	if a == nil {
		return []any{}
	}
	return a
}
func text(v any) string      { s, _ := v.(string); return s }
func connection(v any) []any { return array(object(v)["nodes"]) }
func cursor(v any) string {
	p := object(object(v)["pageInfo"])
	if p["hasNextPage"] == true {
		return text(p["endCursor"])
	}
	return ""
}
func nullCursor(s string) any {
	if s == "" {
		return nil
	}
	return s
}

const pageInfo = `pageInfo { hasNextPage endCursor }`
const cardFields = `id number title url state isDraft updatedAt headRefName reviewDecision mergeable author { login } commits(last:1) { nodes { commit { statusCheckRollup { state } } } }`

var prNumberPattern = regexp.MustCompile(`^#?([1-9][0-9]*)$`)

// GitHub's search doesn't match PR numbers, so a number goes straight to that
// PR, whatever the filters say. A number that isn't a PR is searched as text.
func exactPR(ctx context.Context, r Request) Obj {
	match := prNumberPattern.FindStringSubmatch(strings.TrimSpace(r.Search))
	if match == nil {
		return nil
	}
	number, err := strconv.Atoi(match[1])
	if err != nil {
		return nil
	}
	parts := strings.Split(r.Repo, "/")
	data, err := gql(ctx, `query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){`+cardFields+`}}}`, Obj{"owner": parts[0], "name": parts[1], "number": number})
	if err != nil {
		return nil
	}
	return object(object(data["repository"])["pullRequest"])
}

func list(ctx context.Context, r Request) (any, error) {
	if pr := exactPR(ctx, r); pr != nil {
		return Obj{"items": []any{pr}, "cursors": Obj{}, "total": 1}, nil
	}
	viewer, e := gh(ctx, "api", "user")
	if e != nil {
		return nil, e
	}
	login := text(object(viewer)["login"])
	scope := "repo:" + r.Repo + " is:pr"
	switch r.State {
	case "draft":
		scope += " is:open draft:true"
	case "merged":
		scope += " is:merged"
	case "closed":
		scope += " is:closed is:unmerged"
	case "all":
	case "", "open":
		scope += " is:open"
	default:
		return nil, errors.New("invalid state")
	}
	scope += " sort:updated-desc"
	if strings.TrimSpace(r.Search) != "" {
		scope += " " + r.Search
	}
	filters := map[string]string{"all": ""}
	switch r.Tab {
	case "mine":
		filters = map[string]string{"Created": "author:" + login}
	case "involved":
		// `involves` covers author, assignee, mentions and comments, but not reviews.
		filters = map[string]string{"involves": "involves:" + login, "review-requested": "review-requested:" + login, "reviewed-by": "reviewed-by:" + login}
	case "", "all":
	default:
		return nil, errors.New("invalid tab")
	}
	rows := map[string]Obj{}
	var total any
	next := map[string]string{}
	keys := []string{}
	for k := range filters {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	// Independent cursors avoid losing matches when one involvement category has more pages.
	for _, reason := range keys {
		if len(r.Cursors) > 0 && r.Cursors[reason] == "" {
			continue
		}
		data, e := gql(ctx, `query($q:String!,$cursor:String){search(type:ISSUE,query:$q,first:`+strconv.Itoa(pageSize(r))+`,after:$cursor){issueCount `+pageInfo+` nodes {... on PullRequest {`+cardFields+`}}}}`, Obj{"q": scope + " " + filters[reason], "cursor": nullCursor(r.Cursors[reason])})
		if e != nil {
			return nil, e
		}
		conn := data["search"]
		total = object(conn)["issueCount"]
		if c := cursor(conn); c != "" {
			next[reason] = c
		}
		for _, node := range connection(conn) {
			if pr := object(node); text(pr["id"]) != "" {
				rows[text(pr["id"])] = pr
			}
		}
	}
	result := []any{}
	for _, pr := range rows {
		result = append(result, pr)
	}
	sort.Slice(result, func(i, j int) bool {
		return text(object(result[i])["updatedAt"]) > text(object(result[j])["updatedAt"])
	})
	out := Obj{"items": result, "cursors": next, "viewer": login}
	// Involved searches several ways and they overlap, so it has no single true count.
	if len(filters) == 1 {
		out["total"] = total
	}
	return out, nil
}

const detailQuery = `query($owner:String!,$name:String!,$number:Int!,$comments:String,$reviews:String,$threads:String){repository(owner:$owner,name:$name){mergeCommitAllowed squashMergeAllowed rebaseMergeAllowed autoMergeAllowed pullRequest(number:$number){id number title url body state isDraft headRefName baseRefName headRefOid changedFiles author{login} reviewDecision mergeable mergeStateStatus autoMergeRequest{enabledAt}
 comments(first:100,after:$comments){` + pageInfo + ` nodes{id body url createdAt author{login}}}
 reviews(first:100,after:$reviews){` + pageInfo + ` nodes{id body url submittedAt state author{login}}}
 reviewThreads(first:50,after:$threads){` + pageInfo + ` nodes{id path line isResolved isOutdated viewerCanResolve viewerCanUnresolve viewerCanReply comments(first:100){` + pageInfo + ` nodes{id body url createdAt diffHunk author{login}}}}}
}}}`

func detail(ctx context.Context, r Request) (any, error) {
	parts := strings.Split(r.Repo, "/")
	vars := Obj{"owner": parts[0], "name": parts[1], "number": r.Number}
	var pr Obj
	comments, reviews, threads := []any{}, []any{}, []any{}
	for page := 0; page < 30; page++ {
		data, e := gql(ctx, detailQuery, vars)
		if e != nil {
			return nil, e
		}
		current := object(object(data["repository"])["pullRequest"])
		if current == nil {
			return nil, errors.New("PR not found or inaccessible")
		}
		if pr == nil {
			pr = current
			pr["mergeMethods"] = mergeMethods(object(data["repository"]))
			pr["autoMergeAllowed"] = object(data["repository"])["autoMergeAllowed"]
		}
		for _, key := range []string{"comments", "reviews", "reviewThreads"} {
			param := key
			if key == "reviewThreads" {
				param = "threads"
			}
			if page > 0 && vars[param] == nil {
				continue
			}
			nodes := connection(current[key])
			switch key {
			case "comments":
				comments = append(comments, nodes...)
			case "reviews":
				reviews = append(reviews, nodes...)
			case "reviewThreads":
				threads = append(threads, nodes...)
			}
			vars[param] = nullCursor(cursor(current[key]))
		}
		if vars["comments"] == nil && vars["reviews"] == nil && vars["threads"] == nil {
			break
		}
		if page == 29 {
			return nil, errors.New("conversation exceeds pagination limit; open on GitHub")
		}
	}
	// Fetch additional replies in long threads rather than silently truncating them.
	for _, node := range threads {
		thread := object(node)
		conn := thread["comments"]
		replies := connection(conn)
		for c := cursor(conn); c != ""; c = cursor(conn) {
			data, e := gql(ctx, `query($id:ID!,$cursor:String){node(id:$id){... on PullRequestReviewThread{comments(first:100,after:$cursor){`+pageInfo+` nodes{id body url createdAt diffHunk author{login}}}}}}`, Obj{"id": thread["id"], "cursor": c})
			if e != nil {
				return nil, e
			}
			conn = object(data["node"])["comments"]
			replies = append(replies, connection(conn)...)
		}
		thread["comments"] = replies
	}
	pr["comments"] = comments
	pr["reviews"] = reviews
	pr["threads"] = threads
	delete(pr, "reviewThreads")
	// Its own query: reading a team reviewer can need more access than the PR, and that must not cost the whole view.
	if data, e := gql(ctx, reviewersQuery, Obj{"owner": parts[0], "name": parts[1], "number": r.Number}); e != nil {
		pr["reviewersError"] = e.Error()
		pr["reviewers"] = []any{}
	} else {
		pr["reviewers"] = mergeReviewers(object(object(data["repository"])["pullRequest"]), reviews, text(object(pr["author"])["login"]))
	}
	checks, e := gh(ctx, "pr", "view", strconv.Itoa(r.Number), "--repo", r.Repo, "--json", "statusCheckRollup")
	if e != nil {
		pr["checksError"] = e.Error()
		pr["checks"] = []any{}
	} else {
		pr["checks"] = object(checks)["statusCheckRollup"]
	}
	return pr, nil
}

const reviewersQuery = `query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){
 reviewRequests(first:50){nodes{requestedReviewer{... on User{login} ... on Bot{login} ... on Mannequin{login} ... on Team{combinedSlug}}}}
 latestOpinionatedReviews(first:50){nodes{state author{login}}}
}}}`

// One row per person: their latest opinion, a comment if that is all they left,
// and a waiting request over either, since that is what they owe now.
func mergeReviewers(data Obj, reviews []any, author string) []any {
	rows := []any{}
	seen := map[string]Obj{}
	set := func(login, state string, team bool) {
		if login == "" {
			return
		}
		if row := seen[login]; row != nil {
			row["state"] = state
			return
		}
		seen[login] = Obj{"login": login, "state": state, "team": team}
		rows = append(rows, seen[login])
	}
	for _, n := range connection(data["latestOpinionatedReviews"]) {
		set(text(object(object(n)["author"])["login"]), text(object(n)["state"]), false)
	}
	for _, n := range reviews {
		login := text(object(object(n)["author"])["login"])
		if text(object(n)["state"]) == "COMMENTED" && login != author && seen[login] == nil {
			set(login, "COMMENTED", false)
		}
	}
	for _, n := range connection(data["reviewRequests"]) {
		reviewer := object(object(n)["requestedReviewer"])
		if slug := text(reviewer["combinedSlug"]); slug != "" {
			set(slug, "REQUESTED", true)
		} else {
			set(text(reviewer["login"]), "REQUESTED", false)
		}
	}
	return rows
}

// A login reaches a REST body, so it can only be a name.
var reviewerPattern = regexp.MustCompile(`^[A-Za-z0-9_.\[\]-]+(/[A-Za-z0-9_.-]+)*$`)

// Asking someone who has already reviewed is the same call as adding them.
func requestReviewAgain(ctx context.Context, r Request) (any, error) {
	if r.Number < 1 {
		return nil, errors.New("PR number required")
	}
	if !reviewerPattern.MatchString(r.Reviewer) {
		return nil, fmt.Errorf("%q is not a login or team", r.Reviewer)
	}
	body := Obj{"reviewers": []string{r.Reviewer}}
	if _, team, ok := strings.Cut(r.Reviewer, "/"); ok {
		body = Obj{"team_reviewers": []string{team}}
	}
	_, err := runner(ctx, []string{"api", fmt.Sprintf("repos/%s/pulls/%d/requested_reviewers", r.Repo, r.Number), "--method", "POST", "--input", "-"}, mustJSON(body))
	if err != nil {
		return nil, err
	}
	return Obj{"ok": true}, nil
}

// The ways this repository's settings allow a merge, in GitHub's own order.
func mergeMethods(repo Obj) []any {
	methods := []any{}
	for _, m := range []struct{ field, name string }{{"mergeCommitAllowed", "merge"}, {"squashMergeAllowed", "squash"}, {"rebaseMergeAllowed", "rebase"}} {
		if repo[m.field] == true {
			methods = append(methods, m.name)
		}
	}
	return methods
}

// A merge names the head the person saw, so a push after that is refused rather than merged unseen.
func checkStateChange(r Request) error {
	if r.Number < 1 {
		return errors.New("PR number required")
	}
	switch r.Event {
	case "close", "reopen", "cancel-auto":
		return nil
	case "merge", "squash", "rebase":
		if r.Head == "" {
			return errors.New("head commit required to merge")
		}
		return nil
	case "auto":
		if r.Head == "" {
			return errors.New("head commit required to merge")
		}
		if r.ID == "" {
			return errors.New("pull request ID required for auto-merge")
		}
		if r.Method != "merge" && r.Method != "squash" && r.Method != "rebase" {
			return fmt.Errorf("unknown merge method %q", r.Method)
		}
		return nil
	}
	return fmt.Errorf("unknown state change %q", r.Event)
}

func changeState(ctx context.Context, r Request) (any, error) {
	if err := checkStateChange(r); err != nil {
		return nil, err
	}
	number := strconv.Itoa(r.Number)
	var args []string
	switch r.Event {
	case "close", "reopen":
		args = []string{"pr", r.Event, number, "--repo", r.Repo}
	case "cancel-auto":
		args = []string{"pr", "merge", number, "--repo", r.Repo, "--disable-auto"}
	case "auto":
		// Not `gh pr merge --auto`: with nothing required to wait for, that merges at once,
		// failing checks and all. This asks only for auto-merge, or says why it can't.
		_, err := gql(ctx, `mutation($id:ID!,$method:PullRequestMergeMethod!,$head:GitObjectID!){enablePullRequestAutoMerge(input:{pullRequestId:$id,mergeMethod:$method,expectedHeadOid:$head}){pullRequest{id}}}`, Obj{"id": r.ID, "method": strings.ToUpper(r.Method), "head": r.Head})
		if err != nil {
			return nil, err
		}
		return Obj{"ok": true}, nil
	default:
		args = []string{"pr", "merge", number, "--repo", r.Repo, "--" + r.Event, "--match-head-commit", r.Head}
		// The first line is the commit's subject and the rest its body, as in git.
		if r.Event == "squash" && strings.TrimSpace(r.Body) != "" {
			subject, body, _ := strings.Cut(strings.TrimSpace(r.Body), "\n")
			args = append(args, "--subject", strings.TrimSpace(subject), "--body", strings.TrimSpace(body))
		}
	}
	if _, err := runner(ctx, args, nil); err != nil {
		return nil, err
	}
	return Obj{"ok": true}, nil
}

func branchPRs(ctx context.Context, r Request) (any, error) {
	if strings.TrimSpace(r.Branch) == "" {
		return nil, errors.New("branch is required")
	}
	parts := strings.Split(r.Repo, "/")
	vars := Obj{"owner": parts[0], "name": parts[1], "branch": r.Branch, "cursor": nil}
	items := []any{}
	for {
		data, err := gql(ctx, `query($owner:String!,$name:String!,$branch:String!,$cursor:String){repository(owner:$owner,name:$name){pullRequests(headRefName:$branch,states:[OPEN,CLOSED,MERGED],first:100,after:$cursor,orderBy:{field:UPDATED_AT,direction:DESC}){`+pageInfo+` nodes{`+cardFields+` headRepository{nameWithOwner}}}}}`, vars)
		if err != nil {
			return nil, err
		}
		repository := object(data["repository"])
		if repository == nil {
			return nil, errors.New("repository unavailable")
		}
		conn := repository["pullRequests"]
		for _, node := range connection(conn) {
			pr := object(node)
			if pr["headRefName"] == r.Branch {
				pr["repository"] = r.Repo
				items = append(items, pr)
			}
		}
		next := cursor(conn)
		if next == "" {
			break
		}
		vars["cursor"] = next
	}
	return Obj{"items": items}, nil
}

// A repository is `owner/name`.
func checkRepo(repo string) error {
	parts := strings.Split(repo, "/")
	if len(parts) != 2 {
		return errors.New("repository must be owner/name")
	}
	for _, p := range parts {
		if !segmentPattern.MatchString(p) || p == "." || p == ".." {
			return errors.New("repository must be owner/name")
		}
	}
	return nil
}

func handle(ctx context.Context, r Request) (any, error) {
	if err := checkRepo(r.Repo); err != nil {
		return nil, err
	}
	if tool := r.Tools["github"]; tool != "" {
		ghBinary = tool
	}
	switch r.Action {
	case "branch":
		return branchPRs(ctx, r)
	case "list":
		return list(ctx, r)
	case "detail":
		if r.Number < 1 {
			return nil, errors.New("invalid PR number")
		}
		return detail(ctx, r)
	case "logs":
		if r.Job < 1 {
			return nil, errors.New("invalid job")
		}
		b, err := runner(ctx, []string{"run", "view", "--repo", r.Repo, "--job", strconv.Itoa(r.Job), "--log-failed"}, nil)
		if err != nil {
			return nil, err
		}
		limit := tailBytes(r)
		truncated := len(b) > limit
		if truncated {
			b = b[len(b)-limit:]
		}
		return Obj{"text": string(b), "truncated": truncated}, nil
	case "jobs":
		if r.Run < 1 {
			return nil, errors.New("invalid run")
		}
		return gh(ctx, "api", "--paginate", "--slurp", fmt.Sprintf("repos/%s/actions/runs/%d/jobs?per_page=100", r.Repo, r.Run))
	case "files":
		if r.Number < 1 {
			return nil, errors.New("invalid PR number")
		}
		// GitHub stops at 3000 files and leaves out the patch of a binary or very large file.
		return gh(ctx, "api", "--paginate", "--slurp", fmt.Sprintf("repos/%s/pulls/%d/files?per_page=100", r.Repo, r.Number))
	case "change-state":
		return changeState(ctx, r)
	case "reviewer":
		return requestReviewAgain(ctx, r)
	case "comment":
		if r.Number < 1 || strings.TrimSpace(r.Body) == "" {
			return nil, errors.New("PR number and body required")
		}
		data, e := runner(ctx, []string{"api", fmt.Sprintf("repos/%s/issues/%d/comments", r.Repo, r.Number), "--method", "POST", "--input", "-"}, mustJSON(Obj{"body": r.Body}))
		if e != nil {
			return nil, e
		}
		var v any
		e = json.Unmarshal(data, &v)
		return v, e
	case "reply", "resolve", "reopen":
		if r.Thread == "" {
			return nil, errors.New("thread ID required")
		}
		vars := Obj{"id": r.Thread}
		query := ""
		if r.Action == "reply" {
			if strings.TrimSpace(r.Body) == "" {
				return nil, errors.New("reply required")
			}
			vars["body"] = r.Body
			query = `mutation($id:ID!,$body:String!){addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$id,body:$body}){comment{id}}}`
		} else {
			mutation := "resolveReviewThread"
			if r.Action == "reopen" {
				mutation = "unresolveReviewThread"
			}
			query = `mutation($id:ID!){` + mutation + `(input:{threadId:$id}){thread{id isResolved}}}`
		}
		return gql(ctx, query, vars)
	default:
		return nil, errors.New("unknown action")
	}
}
func mustJSON(v any) []byte { b, _ := json.Marshal(v); return b }
func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: herdr-pr '<JSON request>'")
		os.Exit(1)
	}
	var r Request
	if e := json.Unmarshal([]byte(os.Args[1]), &r); e != nil {
		fmt.Fprintln(os.Stderr, e)
		os.Exit(1)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 26*time.Second)
	defer cancel()
	result, e := handle(ctx, r)
	if e != nil {
		_ = json.NewEncoder(os.Stdout).Encode(Obj{"error": e.Error()})
		os.Exit(1)
	}
	_ = json.NewEncoder(os.Stdout).Encode(result)
}
