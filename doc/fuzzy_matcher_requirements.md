# Fuzzy Matcher Requirements

## Purpose

This document specifies requirements for a standalone fuzzy matching module
that can be used as an alternative to fzf in Gtk3::FzfWidget.  The module
must implement the `Gtk3::FzfWidget::Matcher` interface.

---

## 1. Input

### 1.1 Item loading
- Accept a plain arrayref of strings
- Accept a coderef iterator (called repeatedly, returns arrayref batches or undef when done)
- Items may contain UTF-8 text including multibyte characters
- Items may contain ANSI SGR escape sequences (must be stripped for matching, preserved for display)
- Maximum supported item count: 10,000,000

### 1.2 Dynamic updates
- REQ-INPUT-1: Support appending items after initial load without full reindex
- REQ-INPUT-2: Support replacing the full item list (reload)

---

## 2. Query language

### 2.1 Token splitting
- REQ-QUERY-1: Split query on whitespace; all tokens must match (AND semantics)
- REQ-QUERY-2: OR semantics with `|` separator: `token1 | token2`
- REQ-QUERY-3: Negate a token with `!` prefix: `!word` excludes items containing "word"

### 2.2 Match modes (per token)
- REQ-QUERY-4: Default: fuzzy match (characters appear in order, gaps allowed)
- REQ-QUERY-5: Exact substring: prefix token with `'` (single quote)
- REQ-QUERY-6: Prefix match: suffix token with `^`
- REQ-QUERY-7: Suffix match: suffix token with `$`
- REQ-QUERY-8: Exact whole-word match: prefix and suffix with `'`
- REQ-QUERY-9: Regex match: prefix token with `/`

### 2.3 Case sensitivity
- REQ-QUERY-10: Case-insensitive by default
- REQ-QUERY-11: Case-sensitive when query contains uppercase letters (smart-case)
- REQ-QUERY-12: Force case-sensitive with explicit option

---

## 3. Scoring

### 3.1 Score components (lower = better rank)
- REQ-SCORE-1: Characters closer to the start of the string score better
- REQ-SCORE-2: Consecutive matching characters score better than scattered
- REQ-SCORE-3: Matches at word boundaries (after space, `/`, `.`, `_`, `-`) score better
- REQ-SCORE-4: Matches at uppercase start of camelCase score better
- REQ-SCORE-5: Shorter strings score better than longer ones for equal matches
- REQ-SCORE-6: Exact substring matches score better than fuzzy matches

### 3.2 Score output
- REQ-SCORE-7: Each result includes a numeric score
- REQ-SCORE-8: Each result includes the list of matched character positions (for highlight rendering)

---

## 4. Result set

- REQ-RESULT-1: Results returned in descending score order (best first)
- REQ-RESULT-2: Support returning first N results (limit)
- REQ-RESULT-3: Support returning results starting at offset M (for pagination)
- REQ-RESULT-4: Report total match count separately from the returned slice
- REQ-RESULT-5: Each result: `{ index => N, score => N, text => S, positions => [N,...] }`
- REQ-RESULT-6: Tied scores preserve original insertion order

---

## 5. Performance

- REQ-PERF-1: 10,000 items, any query: result in < 10ms
- REQ-PERF-2: 100,000 items, any query: result in < 100ms
- REQ-PERF-3: 500,000 items, any query: result in < 1000ms
- REQ-PERF-4: Incremental query refinement (query extended by one character) should
  reuse previous results rather than restarting from scratch
- REQ-PERF-5: Thread-safe or re-entrant for use with Glib::Idle async dispatch

---

## 6. API

```perl
my $m = FuzzyMatcher->new(items => \@items, %opts) ;

# Load / reload
$m->set_items(\@items) ;
$m->append_items(\@more_items) ;

# Query
my $results = $m->match($query, limit => 200, offset => 0) ;
# Returns: { matches => [{index,score,text,positions},...], total => N }

# Metadata
$m->item_count() ;    # total items loaded
$m->match_count() ;   # matches for last query

# Options
my $m = FuzzyMatcher->new(
    items       => \@items,
    case        => 'smart',   # 'smart' | 'insensitive' | 'sensitive'
    sort        => 1,         # 0 = preserve insertion order
    ) ;
```

---

## 7. Functionality comparison with fzf

| Feature                  | fzf | Required? |
|--------------------------|-----|-----------|
| Fuzzy match              | yes | yes       |
| Exact substring (`'`)    | yes | yes       |
| Prefix match (`^`)       | yes | yes       |
| Suffix match (`$`)       | yes | yes       |
| Negation (`!`)           | yes | yes       |
| OR logic (`\|`)          | yes | yes       |
| Regex match (`/`)        | yes | optional  |
| Smart-case               | yes | yes       |
| Word-boundary bonus      | yes | yes       |
| CamelCase bonus          | yes | optional  |
| Match positions returned | yes | yes       |
| Pagination (offset)      | yes | yes       |
| Incremental refinement   | yes | optional  |
| ANSI stripping           | yes | yes       |
| UTF-8 support            | yes | yes       |
| Async / non-blocking     | no* | yes (via caller) |

*fzf blocks its HTTP server during search.

---

## 8. What NOT to implement

- Terminal UI (fzf's TUI) — not needed; the widget provides the UI
- Key bindings / actions — handled by FzfWidget
- Preview window — handled by FzfPreview
- Multi-select state — handled by FzfWidget
- Color themes — handled by FzfWidget
- `--listen` HTTP server — replaced by direct Perl API

---

## 9. Suggested Perl implementation approach

Use the Smith-Waterman sequence alignment algorithm (same as fzf) for scoring.
The `Text::Fuzzy` CPAN module provides this.  Alternatively implement a
simpler bonus-based scorer:

```
score = consecutive_bonus * consecutive_count
      + word_boundary_bonus * boundary_count
      + camel_bonus * camel_count
      - gap_penalty * gap_count
      - leading_penalty * leading_spaces
```

For performance at 500k items, use XS or inline C via `Inline::C`.
A pure-Perl implementation with early termination can reach 100k items
in < 100ms.

---

## 10. Modules to evaluate

- `Text::Fuzzy` — XS-based, Smith-Waterman scoring, CPAN
- `String::Similarity` — simpler, pure Perl
- `Search::Fzf` — if it exists on CPAN
- Custom XS via `Inline::C` implementing fzf's algorithm directly
