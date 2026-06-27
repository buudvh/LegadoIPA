# LegadoIPA Project Rules

This document outlines the rules and guidelines for agents working on the LegadoIPA iOS project.

## Code Intelligence with CodeGraph

To optimize token usage, minimize files read, and maintain a precise mental model of the codebase, all agents must use **CodeGraph** (https://github.com/colbymchenry/codegraph) when inspecting or exploring the codebase components.

### 1. Codebase Navigation & Analysis
*   **Search Symbols**: When looking for classes, structs, functions, or variables, run:
    ```bash
    npx.cmd @colbymchenry/codegraph query <symbol_name>
    ```
*   **Explore Symbol Details**: To see a symbol's definition, source code, callers, and callees, run:
    ```bash
    npx.cmd @colbymchenry/codegraph node <symbol_name>
    ```
*   **Trace Relationships**: Use `explore`, `callers`, `callees`, or `impact` commands to check relations and the impact radius of a changes before editing:
    ```bash
    npx.cmd @colbymchenry/codegraph explore <query_terms>
    npx.cmd @colbymchenry/codegraph callers <symbol_name>
    npx.cmd @colbymchenry/codegraph callees <symbol_name>
    ```
*   **Prefer CodeGraph**: Only use raw `grep_search` or `view_file` as fallback options if CodeGraph does not resolve a specific reference.

### 2. Automatic Sync & Index Updates
To ensure CodeGraph's index is always accurate and synchronized with the latest project structure:
*   **Manual Trigger**: Immediately after adding, deleting, renaming, or modifying files/symbols in the project, run:
    ```bash
    npx.cmd @colbymchenry/codegraph sync
    ```
*   **Git Hooks**: Git hooks (`post-commit`, `post-checkout`, `post-merge`) have been configured to automatically run `npx @colbymchenry/codegraph sync` upon branch checkout, merge, or commit operations.

## Quy định Ngôn ngữ (Language Guidelines)

Để đảm bảo tính nhất quán và thuận tiện trong quá trình phát triển dự án này, tất cả các AI agent phải tuân thủ nghiêm ngặt các quy định ngôn ngữ sau:
*   **Ngôn ngữ giao tiếp & trả lời (Replies)**: Mọi câu trả lời, phản hồi, thảo luận hoặc giải thích với người dùng (USER) phải được viết hoàn toàn bằng **tiếng Việt**.
*   **Kế hoạch thực hiện (Plans) & Tài liệu (Documents)**: Tất cả các kế hoạch triển khai thiết kế (`implementation_plan.md`), danh sách nhiệm vụ (`task.md`), báo cáo tổng hợp thay đổi (`walkthrough.md`) và tài liệu liên quan phải được soạn thảo hoàn toàn bằng **tiếng Việt**.

