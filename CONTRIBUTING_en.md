# Contributing to Notepad++ for macOS

***Do not ask what Notepad++ can do for you, ask what you can do for Notepad++.***

---

## 1. Reporting Issues

Bug reports are always welcome. Following these simple guidelines helps resolve issues much faster:

1. Search the issue tracker first to ensure the problem has not already been reported.
2. If you suspect a plugin might be the cause, try renaming the `plugins` folder to disable plugins.
3. Only report bugs regarding standard built-in components to this repository. For 3rd-party plugins, please report them to their respective repositories.
4. Fill in all fields in the issue template. **Debug Information** can be found via the top menu `? > Debug Info...`.

---

## 2. Pull Requests

*First rule of Notepad++: You do not need permission to contribute.*<br/>
*Second rule of Notepad++: Never ask for permission to contribute.*

If you have improvements to contribute, feel free to submit a pull request (PR).<br/>
For graphical enhancements (renaming UI elements, minor typos), please open an issue first. All PRs (except documentation and translations) must be linked to an existing GitHub issue. Feature proposals will be merged after maintainer review (`Accepted` label).

### Pull Request Guidelines

1. Follow existing Notepad++ coding styles strictly. Observe surrounding code and maintain consistency.
2. Create a dedicated branch for each PR (e.g. `feature/ime-fix-2026`).
3. Include only one feature or bug fix per PR.
4. Keep PRs focused and minimize unnecessary full-source formatting churn.
5. PRs modifying only whitespace, indentation, or style without functional value will not be approved.
6. Make sure to build and run the test suite (`make -f Makefile.mac test`) before submitting.

---

## 3. Coding Style

![stay clean](https://notepad-plus-plus.org/assets/images/good-bad-practice.jpg)

### General Rules

1. **Brace Style**: Avoid Java-style braces on classes and methods (except one-line inline headers or `try-catch` blocks).
   - **Correct:**
     ```cpp
     void MyClass::method1()
     {
         if (aCondition)
         {
             // Do something
         }
     }
     ```
   - **Incorrect:**
     ```cpp
     void MyClass::method1() {
         if (aCondition) {
             // Do something
         }
     }
     ```

2. **Tab Usage**: Use Tabs (`\t`) instead of spaces (editor setting: 1 tab = 4 spaces).
3. **Operator Spaces**: Place one space before and after binary/ternary operators (`if (a == 10 && b == 42)`).
4. **For-loop Semicolons**: One space only after semicolons in `for` loops (`for (int i = 0; i != 10; ++i)`).
5. **Function Call Parentheses**: No space between function name and opening parenthesis (`foo();`, `myObject.foo(24);`).
6. **Keyword Parentheses**: One space between control flow keyword and opening parenthesis (`if (true)`, `while (true)`).
7. **Switch Statements**:
   - Maintain proper indentation and put `break;` within brace blocks.
   - For intentional fall-through, specify `[[fallthrough]];`.
8. **Magic Numbers**: Define meaningful named constants or `enum` classes.
9. **Initialization**: Prefer brace initialization (`{}`) (`MyClass instance{10.4};`).
10. **String Empty Check**: Use `!string.empty()` instead of `string != ""`.
11. **C++ Style Casts**: Use `static_cast<char>(x)` instead of C-style casts `(char)x`.
12. **Variable Initialization**: Always initialize local and member variables.

### Naming Conventions

1. **Class Names**: PascalCase (`class MyDocumentManager {};`)
2. **Methods & Parameters**: camelCase (`void doSomething(int documentIndex);`)
3. **Member Variables**: Prefix with underscore (`int _tabCount;`) or `m` prefix (`std::vector<NppDocument> mDocuments;`)
4. **Descriptive Names**: Use clear, descriptive identifiers (`if (hours < 24 && minutes < 60)`).

### Comments

- Prefer C++ line comments (`// ...`) over C-style block comments (`/* ... */`).

### Best Practices

1. Leverage modern C++20 standard library features wherever appropriate.
2. Prefer prefix increment (`++i`) over postfix increment (`i++`).
