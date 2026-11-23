package main

import (
	"context"
	"encoding/json"
	"errors"
	"os/exec"
	"reflect"
	"strings"
	"testing"
)

func mock(t *testing.T, f func([]string, []byte) ([]byte, error)) {
	old := runner
	t.Cleanup(func() { runner = old })
	runner = func(_ context.Context, a []string, b []byte) ([]byte, error) { return f(a, b) }
}
func payload(t *testing.T, b []byte) Obj {
	t.Helper()
	var p Obj
	if e := json.Unmarshal(b, &p); e != nil {
		t.Fatal(e)
	}
	return p
}
func conn(nodes []any, next string) Obj {
	return Obj{"nodes": nodes, "pageInfo": Obj{"hasNextPage": next != "", "endCursor": next}}
}
func TestInvolvementUnionAndIndependentPagination(t *testing.T) {
	calls := 0
	mock(t, func(a []string, b []byte) ([]byte, error) {
		if reflect.DeepEqual(a, []string{"api", "user"}) {
			return mustJSON(Obj{"login": "me"}), nil
		}
		calls++
		v := object(payload(t, b)["variables"])
		q := text(v["q"])
		if !strings.Contains(q, "repo:owner/repo is:pr is:open") {
			t.Fatal(q)
		}
		next := ""
		if strings.Contains(q, "reviewed-by:") {
			next = "comment-next"
		}
		return mustJSON(Obj{"data": Obj{"search": conn([]any{Obj{"id": "pr", "updatedAt": "2026-01-01"}}, next)}}), nil
	})
	got, e := list(context.Background(), Request{Repo: "owner/repo", Tab: "involved"})
	if e != nil {
		t.Fatal(e)
	}
	out := object(got)
	if len(array(out["items"])) != 1 || calls != 3 {
		t.Fatalf("%v, calls %d", out, calls)
	}
	calls = 0
	_, e = list(context.Background(), Request{Repo: "owner/repo", Tab: "involved", Cursors: map[string]string{"reviewed-by": "comment-next"}})
	if e != nil {
		t.Fatal(e)
	}
	if calls != 1 {
		t.Fatalf("expected only unfinished category, got %d calls", calls)
	}
}
func TestDetailPaginatesConversationAndThreadReplies(t *testing.T) {
	pages := 0
	mock(t, func(a []string, b []byte) ([]byte, error) {
		if a[0] == "pr" {
			return mustJSON(Obj{"statusCheckRollup": []any{}}), nil
		}
		v := object(payload(t, b)["variables"])
		if v["id"] == "thread" {
			return mustJSON(Obj{"data": Obj{"node": Obj{"comments": conn([]any{Obj{"id": "reply2"}}, "")}}}), nil
		}
		pages++
		pr := Obj{"id": "pr", "comments": conn([]any{Obj{"id": "comment1"}}, "page2"), "reviews": conn([]any{}, ""), "reviewThreads": conn([]any{Obj{"id": "thread", "comments": conn([]any{Obj{"id": "reply1"}}, "more-replies")}}, "")}
		if pages == 2 {
			if v["comments"] != "page2" {
				t.Fatal(v)
			}
			pr["comments"] = conn([]any{Obj{"id": "comment2"}}, "")
		}
		return mustJSON(Obj{"data": Obj{"repository": Obj{"pullRequest": pr}}}), nil
	})
	got, e := detail(context.Background(), Request{Repo: "owner/repo", Number: 1})
	if e != nil {
		t.Fatal(e)
	}
	pr := object(got)
	if len(array(pr["comments"])) != 2 || len(array(pr["threads"])) != 1 || len(array(object(array(pr["threads"])[0])["comments"])) != 2 {
		t.Fatal(pr)
	}
}
func TestCommentBodyIsJSONNotShell(t *testing.T) {
	body := "quotes ' \" and $(touch bad)\nline two"
	mock(t, func(a []string, b []byte) ([]byte, error) {
		if !reflect.DeepEqual(a, []string{"api", "repos/owner/repo/issues/2/comments", "--method", "POST", "--input", "-"}) {
			t.Fatal(a)
		}
		if payload(t, b)["body"] != body {
			t.Fatal(string(b))
		}
		return []byte(`{"id":1}`), nil
	})
	if _, e := handle(context.Background(), Request{Action: "comment", Repo: "owner/repo", Number: 2, Body: body}); e != nil {
		t.Fatal(e)
	}
}
func TestGraphQLErrorsFailEvenWithData(t *testing.T) {
	mock(t, func(a []string, b []byte) ([]byte, error) {
		return []byte(`{"data":{},"errors":[{"message":"no access"}]}`), nil
	})
	if _, e := gql(context.Background(), "query{}", nil); e == nil {
		t.Fatal("expected error")
	}
}
func TestMutations(t *testing.T) {
	for _, action := range []string{"reply", "resolve", "reopen"} {
		t.Run(action, func(t *testing.T) {
			mock(t, func(a []string, b []byte) ([]byte, error) {
				v := object(payload(t, b)["variables"])
				if v["id"] != "thread" {
					t.Fatal(v)
				}
				if action == "reply" && v["body"] != "response" {
					t.Fatal(v)
				}
				return []byte(`{"data":{}}`), nil
			})
			if _, e := handle(context.Background(), Request{Action: action, Repo: "owner/repo", Thread: "thread", Body: "response"}); e != nil {
				t.Fatal(e)
			}
		})
	}
	if _, e := handle(context.Background(), Request{Action: "list", Repo: "../bad"}); e == nil {
		t.Fatal("expected validation error")
	}
}

func TestBranchPRsMatchesExactBranchAndPaginates(t *testing.T) {
	pages := 0
	mock(t, func(args []string, b []byte) ([]byte, error) {
		vars := object(payload(t, b)["variables"])
		if vars["branch"] != "feature/x" {
			t.Fatal(vars)
		}
		pages++
		next := "next"
		if pages == 2 {
			next = ""
			if vars["cursor"] != "next" {
				t.Fatal(vars)
			}
		}
		return mustJSON(Obj{"data": Obj{"repository": Obj{"pullRequests": conn([]any{Obj{"id": pages, "headRefName": "feature/x"}, Obj{"id": "other", "headRefName": "feature/y"}}, next)}}}), nil
	})
	result, err := handle(context.Background(), Request{Action: "branch", Repo: "owner/repo", Branch: "feature/x"})
	if err != nil {
		t.Fatal(err)
	}
	items := array(object(result)["items"])
	if len(items) != 2 || object(items[0])["repository"] != "owner/repo" {
		t.Fatal(items)
	}
}

func TestDraftMergedAndClosedFilters(t *testing.T) {
	for state, qualifier := range map[string]string{"draft": "is:open draft:true", "merged": "is:merged", "closed": "is:closed is:unmerged"} {
		t.Run(state, func(t *testing.T) {
			mock(t, func(args []string, b []byte) ([]byte, error) {
				if len(b) == 0 {
					return mustJSON(Obj{"login": "me"}), nil
				}
				q := text(object(payload(t, b)["variables"])["q"])
				if !strings.Contains(q, qualifier) {
					t.Fatal(q)
				}
				return mustJSON(Obj{"data": Obj{"search": conn([]any{}, "")}}), nil
			})
			if _, err := list(context.Background(), Request{Repo: "owner/repo", State: state}); err != nil {
				t.Fatal(err)
			}
		})
	}
}

func TestGhErrorsAreExplained(t *testing.T) {
	notFound := &exec.Error{Name: "gh", Err: exec.ErrNotFound}
	if e := describeGhError(notFound, ""); !strings.Contains(e.Error(), "not installed") {
		t.Fatal(e)
	}
	if e := describeGhError(errors.New("exit status 4"), "To get started with GitHub CLI, please run:  gh auth login"); !strings.Contains(e.Error(), "not logged in") {
		t.Fatal(e)
	}
	if e := describeGhError(errors.New("exit status 1"), "boom"); !strings.Contains(e.Error(), "boom") {
		t.Fatal(e)
	}
}

func TestChangeStateRunsTheMatchingGhCommand(t *testing.T) {
	var got []string
	mock(t, func(args []string, _ []byte) ([]byte, error) { got = args; return []byte("Merged\n"), nil })
	cases := map[string][]string{
		"merge":       {"pr", "merge", "42", "--repo", "owner/repo", "--merge", "--match-head-commit", "abc"},
		"squash":      {"pr", "merge", "42", "--repo", "owner/repo", "--squash", "--match-head-commit", "abc"},
		"rebase":      {"pr", "merge", "42", "--repo", "owner/repo", "--rebase", "--match-head-commit", "abc"},
		"close":       {"pr", "close", "42", "--repo", "owner/repo"},
		"reopen":      {"pr", "reopen", "42", "--repo", "owner/repo"},
		"cancel-auto": {"pr", "merge", "42", "--repo", "owner/repo", "--disable-auto"},
	}
	for event, want := range cases {
		if _, err := handle(context.Background(), Request{Action: "change-state", Repo: "owner/repo", Number: 42, Event: event, Head: "abc"}); err != nil {
			t.Fatal(event, err)
		}
		if !reflect.DeepEqual(got, want) {
			t.Fatalf("%s ran %v", event, got)
		}
	}
	if _, err := handle(context.Background(), Request{Action: "change-state", Repo: "owner/repo", Number: 42, Event: "squash", Head: "abc", Body: "Fix it (#42)\n\nBecause.\nReally."}); err != nil {
		t.Fatal(err)
	}
	if want := append(cases["squash"][:len(cases["squash"]):len(cases["squash"])], "--subject", "Fix it (#42)", "--body", "Because.\nReally."); !reflect.DeepEqual(got, want) {
		t.Fatalf("squash message ran %v", got)
	}
	if _, err := handle(context.Background(), Request{Action: "change-state", Repo: "owner/repo", Number: 42, Event: "merge", Head: "abc", Body: "ignored"}); err != nil || !reflect.DeepEqual(got, cases["merge"]) {
		t.Fatalf("a plain merge took a message: %v %v", got, err)
	}
	got = nil
	for _, r := range []Request{{Event: "merge"}, {Event: "delete", Head: "abc"}, {Event: "--admin", Head: "abc"}, {Event: "auto", ID: "pr", Head: "abc"}, {Event: "auto", ID: "pr", Method: "--admin", Head: "abc"}, {Event: "auto", ID: "pr", Method: "squash"}, {Event: "auto", Method: "squash", Head: "abc"}} {
		r.Action, r.Repo, r.Number = "change-state", "owner/repo", 42
		if _, err := handle(context.Background(), r); err == nil || got != nil {
			t.Fatalf("%+v was not refused, ran %v", r, got)
		}
	}
}

func TestMergeMethodsFollowTheRepositorySettings(t *testing.T) {
	got := mergeMethods(Obj{"mergeCommitAllowed": false, "squashMergeAllowed": true, "rebaseMergeAllowed": true})
	if !reflect.DeepEqual(got, []any{"squash", "rebase"}) {
		t.Fatal(got)
	}
}

func TestMergeReviewersShowsEachPersonsCurrentStanding(t *testing.T) {
	data := Obj{
		"latestOpinionatedReviews": Obj{"nodes": []any{
			Obj{"state": "APPROVED", "author": Obj{"login": "ann"}},
			Obj{"state": "CHANGES_REQUESTED", "author": Obj{"login": "bob"}},
			Obj{"state": "APPROVED", "author": Obj{"login": "cat"}},
		}},
		"reviewRequests": Obj{"nodes": []any{
			Obj{"requestedReviewer": Obj{"login": "cat"}},
			Obj{"requestedReviewer": Obj{"login": "dan"}},
			Obj{"requestedReviewer": Obj{"combinedSlug": "org/core"}},
			Obj{"requestedReviewer": Obj{}},
		}},
	}
	reviews := []any{
		Obj{"state": "COMMENTED", "author": Obj{"login": "eve"}},
		Obj{"state": "COMMENTED", "author": Obj{"login": "ann"}},
		Obj{"state": "COMMENTED", "author": Obj{"login": "owner"}},
	}
	got := map[string]string{}
	for _, row := range mergeReviewers(data, reviews, "owner") {
		got[text(object(row)["login"])] = text(object(row)["state"])
	}
	want := map[string]string{"ann": "APPROVED", "bob": "CHANGES_REQUESTED", "cat": "REQUESTED", "dan": "REQUESTED", "org/core": "REQUESTED", "eve": "COMMENTED"}
	if !reflect.DeepEqual(got, want) {
		t.Fatal(got)
	}
}

func TestRequestReviewAgain(t *testing.T) {
	var args []string
	var input Obj
	mock(t, func(a []string, in []byte) ([]byte, error) {
		args = a
		input = Obj{}
		_ = json.Unmarshal(in, &input)
		return []byte("{}"), nil
	})
	run := func(who string) error {
		_, err := handle(context.Background(), Request{Action: "reviewer", Repo: "owner/repo", Number: 42, Reviewer: who})
		return err
	}
	if err := run("ann"); err != nil || args[1] != "repos/owner/repo/pulls/42/requested_reviewers" || args[3] != "POST" || !reflect.DeepEqual(input["reviewers"], []any{"ann"}) {
		t.Fatal(args, input, err)
	}
	if err := run("org/core"); err != nil || !reflect.DeepEqual(input["team_reviewers"], []any{"core"}) {
		t.Fatal(args, input, err)
	}
	args = nil
	for _, bad := range []string{"", "ann\n/close", "@ann me"} {
		if err := run(bad); err == nil || args != nil {
			t.Fatalf("%q was not refused, ran %v", bad, args)
		}
	}
}

func TestOnlyGitHubRepositoriesAreAccepted(t *testing.T) {
	for _, repo := range []string{"gitlab.com/group/project", "owner", "owner/repo/extra", "../bad"} {
		if _, err := handle(context.Background(), Request{Action: "list", Repo: repo}); err == nil {
			t.Fatalf("%q was accepted", repo)
		}
	}
}

func TestListReportsGitHubsTotalOnlyWhenOneSearchAnswers(t *testing.T) {
	mock(t, func(a []string, b []byte) ([]byte, error) {
		if reflect.DeepEqual(a, []string{"api", "user"}) {
			return mustJSON(Obj{"login": "me"}), nil
		}
		search := conn([]any{Obj{"id": "pr", "updatedAt": "2026-01-01"}}, "next")
		search["issueCount"] = 137
		return mustJSON(Obj{"data": Obj{"search": search}}), nil
	})
	got, e := list(context.Background(), Request{Repo: "owner/repo"})
	if e != nil || object(got)["total"] != float64(137) {
		t.Fatalf("%v %v", got, e)
	}
	got, e = list(context.Background(), Request{Repo: "owner/repo", Tab: "involved"})
	if _, has := object(got)["total"]; e != nil || has {
		t.Fatalf("%v %v", got, e)
	}
}

func TestANumberFindsThatPRWhateverTheFilters(t *testing.T) {
	asked := []string{}
	mock(t, func(a []string, b []byte) ([]byte, error) {
		if reflect.DeepEqual(a, []string{"api", "user"}) {
			asked = append(asked, "user")
			return mustJSON(Obj{"login": "me"}), nil
		}
		v := object(payload(t, b)["variables"])
		if v["number"] == float64(482) {
			asked = append(asked, "exact")
			return mustJSON(Obj{"data": Obj{"repository": Obj{"pullRequest": Obj{"id": "pr", "number": 482}}}}), nil
		}
		if v["number"] != nil {
			asked = append(asked, "missing")
			return mustJSON(Obj{"data": Obj{"repository": Obj{"pullRequest": nil}}}), nil
		}
		asked = append(asked, "search")
		return mustJSON(Obj{"data": Obj{"search": conn([]any{}, "")}}), nil
	})
	got, e := list(context.Background(), Request{Repo: "owner/repo", Search: "#482", State: "merged"})
	if e != nil || len(array(object(got)["items"])) != 1 || !reflect.DeepEqual(asked, []string{"exact"}) {
		t.Fatalf("%v %v %v", got, e, asked)
	}
	asked = nil
	if _, e = list(context.Background(), Request{Repo: "owner/repo", Search: "7"}); e != nil || !reflect.DeepEqual(asked, []string{"missing", "user", "search"}) {
		t.Fatalf("%v %v", e, asked)
	}
	asked = nil
	if _, e = list(context.Background(), Request{Repo: "owner/repo", Search: "offline 7"}); e != nil || !reflect.DeepEqual(asked, []string{"user", "search"}) {
		t.Fatalf("%v %v", e, asked)
	}
}

func TestAGhPathThatDoesNotExistCountsAsMissing(t *testing.T) {
	old := ghBinary
	t.Cleanup(func() { ghBinary = old })
	ghBinary = "/nonexistent/gh"
	_, err := runCommand(context.Background(), []string{"api", "user"}, nil)
	if err == nil || !strings.Contains(err.Error(), "is not installed") {
		t.Fatalf("got %v", err)
	}
}

// `gh pr merge --auto` merges at once when nothing is required; that must never run.
func TestAutoMergeAsksGitHubForAutoMergeAndNeverMerges(t *testing.T) {
	var vars Obj
	var query string
	mock(t, func(a []string, b []byte) ([]byte, error) {
		if !reflect.DeepEqual(a, []string{"api", "graphql", "--input", "-"}) {
			t.Fatalf("ran %v", a)
		}
		p := payload(t, b)
		query, vars = text(p["query"]), object(p["variables"])
		return []byte(`{"data":{}}`), nil
	})
	r := Request{Action: "change-state", Repo: "owner/repo", Number: 42, Event: "auto", ID: "PR_1", Method: "squash", Head: "abc"}
	if _, err := handle(context.Background(), r); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(query, "enablePullRequestAutoMerge") || vars["method"] != "SQUASH" || vars["head"] != "abc" || vars["id"] != "PR_1" {
		t.Fatalf("%s %v", query, vars)
	}
	mock(t, func(a []string, b []byte) ([]byte, error) {
		return mustJSON(Obj{"errors": []any{Obj{"message": "Pull request is in clean status"}}}), nil
	})
	if _, err := handle(context.Background(), r); err == nil || !strings.Contains(err.Error(), "clean status") {
		t.Fatalf("GitHub's refusal was lost: %v", err)
	}
}

func TestFilesReadsEveryPageOfThePRsFiles(t *testing.T) {
	mock(t, func(a []string, _ []byte) ([]byte, error) {
		if !reflect.DeepEqual(a, []string{"api", "--paginate", "--slurp", "repos/owner/repo/pulls/5/files?per_page=100"}) {
			t.Fatal(a)
		}
		return []byte(`[[{"filename":"a.go"}]]`), nil
	})
	if _, e := handle(context.Background(), Request{Action: "files", Repo: "owner/repo", Number: 5}); e != nil {
		t.Fatal(e)
	}
	if _, e := handle(context.Background(), Request{Action: "files", Repo: "owner/repo"}); e == nil {
		t.Fatal("a missing number must fail")
	}
}
