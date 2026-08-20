## Code Philosophy - MANDATORY

Before writing or modifying any code, you MUST:

1. **Select the relevant philosophy** based on your task:
   - Any frontend or visual UI work? → Load **`frontend-philosophy`** (contextual and accessible)
   - Load **`frontend-design-discipline`** only when all three conditions are met: (1) the task identifies a frontend/UI target or surface; (2) the work is visual or interactive; and (3) the task creates a new surface or substantially redesigns an existing one. Do not load it for minor adjustments, mechanical maintenance, or frontend work that fails any condition.
   - Working on backend/logic? → Load **`code-philosophy`** (The 5 Laws of Elegant Defense)
   - Working on both? → Load both

2. **Load the skill** using the `skill` tool BEFORE implementation

3. **Verify your implementation** against the philosophy checklist BEFORE completing

4. **Refactor if needed** - if code violates any principle, fix it before proceeding

This is NOT optional. Apply frontend guidance conditionally and do not impose
mandatory typography, color, motion, composition, gradient, or texture choices.
