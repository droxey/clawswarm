---
name: humanizer
description: |
  Remove signs of AI-generated writing from text. Detects 24 AI writing
  patterns from Wikipedia's Signs of AI writing guide. Do not use for
  technical documentation, API references, or code comments.
---

# Humanizer: Remove AI Writing Patterns

Identify and remove signs of AI-generated text to make writing sound natural and human. Based on Wikipedia's "Signs of AI writing" page, maintained by WikiProject AI Cleanup.

## Procedure

1. Scan the input text for AI patterns listed in `references/ai-writing-patterns.md`.
2. Rewrite problematic sections, replacing AI patterns with natural alternatives.
3. Preserve the core meaning of the original text.
4. Match the intended tone (formal, casual, technical, etc.).
5. Add personality — sterile, voiceless writing is just as obvious as slop. See the guidance below.
6. Present a draft rewrite.
7. Run an anti-AI audit: ask "What makes the below so obviously AI generated?" and list remaining tells.
8. Revise the draft to eliminate remaining tells. Present the final version.

---

## Personality and soul

Removing AI patterns is only half the job. Good writing has a human behind it.

**Signs of soulless writing (even if technically "clean"):**
- Every sentence is the same length and structure
- No opinions, just neutral reporting
- No acknowledgment of uncertainty or mixed feelings
- No first-person perspective when appropriate
- No humor, no edge, no personality
- Reads like a Wikipedia article or press release

**How to add voice:**
- **Have opinions.** React to facts instead of neutrally listing them.
- **Vary rhythm.** Mix short punchy sentences with longer ones.
- **Acknowledge complexity.** "This is impressive but also kind of unsettling" beats "This is impressive."
- **Use "I" when it fits.** First person is honest, not unprofessional.
- **Let some mess in.** Perfect structure feels algorithmic.
- **Be specific about feelings.** Not "this is concerning" but concrete descriptions.

---

## AI pattern checklist

Scan for these 24 patterns. Read `references/ai-writing-patterns.md` for the complete catalog with before/after examples.

**Content patterns:**
1. Undue emphasis on significance, legacy, and broader trends
2. Undue emphasis on notability and media coverage
3. Superficial analyses with -ing endings
4. Promotional and advertisement-like language
5. Vague attributions and weasel words
6. Outline-like "Challenges and Future Prospects" sections

**Language and grammar patterns:**
7. Overused "AI vocabulary" words
8. Avoidance of "is"/"are" (copula avoidance)
9. Negative parallelisms
10. Rule of three overuse
11. Elegant variation (synonym cycling)
12. False ranges

**Style patterns:**
13. Em dash overuse
14. Overuse of boldface
15. Inline-header vertical lists
16. Title case in headings
17. Emojis
18. Curly quotation marks

**Communication patterns:**
19. Collaborative communication artifacts
20. Knowledge-cutoff disclaimers
21. Sycophantic/servile tone

**Filler and hedging:**
22. Filler phrases
23. Excessive hedging
24. Generic positive conclusions

---

## Output format

1. Draft rewrite
2. Anti-AI audit: "What makes the below so obviously AI generated?" (brief bullets)
3. Final rewrite
4. Summary of changes made (optional)

See `assets/humanizer-example.md` for a complete worked example.

---

## Reference

Based on [Wikipedia:Signs of AI writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing), maintained by WikiProject AI Cleanup. "LLMs use statistical algorithms to guess what should come next. The result tends toward the most statistically likely result that applies to the widest variety of cases."
