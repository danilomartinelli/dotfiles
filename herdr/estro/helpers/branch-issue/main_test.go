package main

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func mock(t *testing.T, f func(payload Obj) (int, []byte)) {
	oldT, oldR := transport, readKey
	t.Cleanup(func() { transport, readKey = oldT, oldR })
	readKey = func() (string, error) { return "lin_api_test", nil }
	transport = func(_ context.Context, key string, b []byte) (int, []byte, error) {
		if key != "lin_api_test" {
			t.Fatalf("unexpected key %q", key)
		}
		var p Obj
		if err := json.Unmarshal(b, &p); err != nil {
			t.Fatal(err)
		}
		status, body := f(p)
		return status, body, nil
	}
}
func mustJSON(v any) []byte { b, _ := json.Marshal(v); return b }
func conn(items []any, next string) Obj {
	return Obj{"nodes": items, "pageInfo": Obj{"hasNextPage": next != "", "endCursor": next}}
}

func TestListFilterCombinesScopeStateTeamAndSearch(t *testing.T) {
	var got Obj
	mock(t, func(p Obj) (int, []byte) {
		got = object(object(p["variables"])["filter"])
		return 200, mustJSON(Obj{"data": Obj{"issues": conn([]any{Obj{"id": "i1"}}, "next")}})
	})
	out, err := list(context.Background(), "lin_api_test", Request{Scope: "mine", State: "started", Team: "ENG", Search: "eng-42"})
	if err != nil {
		t.Fatal(err)
	}
	if object(got["assignee"]) == nil || object(got["team"]) == nil || len(array(got["or"])) != 3 {
		t.Fatalf("filter %v", got)
	}
	if types := array(object(object(got["state"])["type"])["in"]); len(types) != 1 || types[0] != "started" {
		t.Fatalf("state filter %v", got["state"])
	}
	if text(object(out)["cursor"]) != "next" || len(array(object(out)["items"])) != 1 {
		t.Fatalf("result %v", out)
	}
	if _, err := list(context.Background(), "lin_api_test", Request{Scope: "bogus"}); err == nil {
		t.Fatal("expected invalid scope")
	}
}

func TestResolveDropsUnknownIdentifiersAndPaginatesComments(t *testing.T) {
	mock(t, func(p Obj) (int, []byte) {
		q := text(p["query"])
		v := object(p["variables"])
		if strings.Contains(q, "comments(first:100,after:$after)") {
			return 200, mustJSON(Obj{"data": Obj{"issue": Obj{"comments": conn([]any{Obj{"id": "c2"}}, "")}}})
		}
		if v["team"] == "ENG" {
			issue := Obj{"id": "uuid", "identifier": "ENG-7", "comments": conn([]any{Obj{"id": "c1"}}, "more"), "team": Obj{"states": conn([]any{Obj{"id": "s"}}, ""), "members": conn([]any{}, "")}}
			return 200, mustJSON(Obj{"data": Obj{"issues": conn([]any{issue}, "")}})
		}
		return 200, mustJSON(Obj{"data": Obj{"issues": conn([]any{}, "")}})
	})
	out, err := handle(context.Background(), Request{Action: "resolve", Identifiers: []string{"ENG-7", "FIX-123", "not-an-id", "main"}})
	if err != nil {
		t.Fatal(err)
	}
	items := array(object(out)["items"])
	if len(items) != 1 {
		t.Fatalf("items %v", items)
	}
	issue := object(items[0])
	if len(array(issue["comments"])) != 2 || len(array(object(issue["team"])["states"])) != 1 {
		t.Fatalf("issue %v", issue)
	}
	if _, err := handle(context.Background(), Request{Action: "detail", Identifier: "FIX-123"}); err == nil || !strings.Contains(err.Error(), "not found") {
		t.Fatalf("expected not found, got %v", err)
	}
}

func TestMutationsAndKeyErrors(t *testing.T) {
	var last Obj
	mock(t, func(p Obj) (int, []byte) {
		last = p
		if strings.Contains(text(p["query"]), "viewer{") {
			return 200, mustJSON(Obj{"data": Obj{"viewer": Obj{"id": "me"}, "teams": conn([]any{Obj{"key": "ENG"}}, "")}})
		}
		return 200, mustJSON(Obj{"data": Obj{"ok": true}})
	})
	if _, err := handle(context.Background(), Request{Action: "comment", Issue: "uuid", Body: "hi", Parent: "root"}); err != nil {
		t.Fatal(err)
	}
	if v := object(last["variables"]); v["parent"] != "root" || !strings.Contains(text(last["query"]), "commentCreate") {
		t.Fatalf("comment %v", last)
	}
	five := 5
	if _, err := handle(context.Background(), Request{Action: "update", Issue: "uuid", Priority: &five}); err == nil {
		t.Fatal("expected priority range error")
	}
	if _, err := handle(context.Background(), Request{Action: "update", Issue: "uuid", Unassign: true, StateID: "s2"}); err != nil {
		t.Fatal(err)
	}
	input := object(object(last["variables"])["input"])
	if _, ok := input["assigneeId"]; !ok || input["assigneeId"] != nil || input["stateId"] != "s2" {
		t.Fatalf("update input %v", input)
	}
	if _, err := handle(context.Background(), Request{Action: "update", Issue: "uuid"}); err == nil {
		t.Fatal("expected nothing to update")
	}
	out, err := handle(context.Background(), Request{Action: "viewer"})
	if err != nil || len(array(object(out)["teams"])) != 1 {
		t.Fatalf("viewer %v %v", out, err)
	}
	readKey = func() (string, error) { return "", missingKey }
	if _, err := handle(context.Background(), Request{Action: "viewer"}); err == nil || !strings.Contains(err.Error(), "LINEAR_API_KEY is not set") {
		t.Fatalf("expected missing key, got %v", err)
	}
	readKey = func() (string, error) { return "lin_api_test", nil }
	transport = func(context.Context, string, []byte) (int, []byte, error) { return 401, []byte(`{}`), nil }
	if _, err := handle(context.Background(), Request{Action: "viewer"}); err == nil || !strings.Contains(err.Error(), "rejected") {
		t.Fatalf("expected rejected key, got %v", err)
	}
}

func TestLoadKeyIgnoresAShellGreeting(t *testing.T) {
	shell := filepath.Join(t.TempDir(), "shell.sh")
	script := "#!/bin/sh\nLINEAR_API_KEY=secret\necho Welcome back\neval \"$2\"\n"
	if err := os.WriteFile(shell, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("LINEAR_API_KEY", "")
	t.Setenv("SHELL", shell)
	if key, err := loadKey(); err != nil || key != "secret" {
		t.Fatalf("got %q %v", key, err)
	}
}

func TestABareNumberSearchesThatNumberInAnyTeam(t *testing.T) {
	filter, err := listFilter(Request{Search: "#42"})
	if err != nil {
		t.Fatal(err)
	}
	or := array(filter["or"])
	if len(or) != 3 || object(object(or[2])["number"])["eq"] != 42 {
		t.Fatalf("filter %v", or)
	}
	filter, _ = listFilter(Request{Search: "login"})
	if len(array(filter["or"])) != 2 {
		t.Fatalf("text search %v", filter)
	}
}
