# Interra Project & Design Engineering Guidelines

## Core Principles (Anti-Slop & Design Craft)
- Follow the `unslop` and `ui-ux-pro-max` design engineering standards on every UI task.
- Never produce generic "AI-slop" or default plain templates:
  - No generic purple/indigo glowing gradient blobs.
  - No random emoji labels in buttons or lists.
  - Keep chrome quiet (subtle 1px borders, tinted neutrals, single accent). Put visual richness into content moments (real speed charts, live pulse indicators, rich cards).
  - Use modern 21st.dev / Magic UI / shadcn design patterns:
    * Number Ticker / Rolling counters for balances and metrics.
    * Live Pulse Dots (green for active, amber/red for restricted) instead of plain text badges.
    * Morphing animated copy buttons with light haptic feedback.
    * Bento Grid layouts for services and features instead of endless vertical lists.
    * Vaul-style bottom sheets with smooth drag handles, backdrop blur, and sticky CTAs.

## Mobile (Flutter in `app/`)
- Ensure all touch targets are at least 44x44 dp.
- Use smooth spring physics (`Curves.easeOutCubic`, `Curves.easeOutExpo`).
- Support theme tokens and dark mode natively (`AppColors`, `AppTheme`).

## Web & Admin UI (`server/admin-ui/`)
- Modern React + Tailwind CSS with clean component hierarchy.
- Bento cards with subtle border illumination on hover.

## No Consultation Traps or Option Interrogations
- Never dump multiple-choice questionnaires on the user ("Вопрос 1 / Вариант A / Вариант B / Твое решение?").
- Take engineering initiative: choose modern industry standards yourself (Next.js/React + Tailwind + shadcn/21st.dev, clean typography, system palette) and show working code/prototypes.
- If a clarifying decision is truly required, ask at most one single direct question in plain text without academic choices or test forms.

## Human Communication & Writing (detect-ai-text / ВП:ПРГЕН Always-On)
- Always write in Russian, natural, direct, human tone.
- Lowercase, small hyphens `-` (never use long em-dash `—`).
- No dot/period at the very end of the message.
- No markdown monospaced backticks in chat text.
- Strictly eliminate all LLM markers and AI artifacts (WP:PRGEN / ВП:ПРГЕН):
  - No assistant boilerplate or service filler ("Конечно", "Надеюсь, это помогло", "Дай знать, если нужно", "Жду твоих решений", "Чтобы двигаться дальше").
  - No didactic hedging ("важно отметить", "следует учесть", "стоит подчеркнуть", "необходимо понимать").
  - No synthetic evaluative clichés ("играет ключевую роль", "не только... но и...", "богатый опыт", "яркий пример", "идеальная совместимость", "прямо из коробки").
  - No artificial "rule of three" lists or robotic parallelisms.
  - Write factually, authentically, and casually, like a real dev peer talking in chat.
