# Sublimate Development Guidelines

## macOS UI Design Standards

When creating forms and UI components in this app, follow these macOS design principles:

### Form Design

#### Layout
- Use `Form` with `.formStyle(.grouped)` for grouped sections
- Provide adequate padding: `.padding(20)` on the form container
- Set reasonable window sizes: `.frame(width:, height:)` on NavigationStack
- Group related fields in `Section` with clear headers

#### Text Fields
- Always set minimum widths: `.frame(minWidth: 300)` for standard fields
- Use `TextField` for single-line input (not `SecureField` unless for passwords)
- Provide `.help()` tooltips for fields that need clarification
- Use descriptive placeholder text

#### Pickers
- Use standard `Picker` with clear labels
- For optional selections, include a "Select..." option tagged as `nil`
- Make sure selected items conform to `Hashable` if needed

#### Date Inputs
- Show date pickers directly, don't hide behind toggles
- Add checkboxes like "No expiration" or "No start date" alongside pickers
- Disable and fade pickers (`.disabled()` + `.opacity(0.5)`) when checkbox is active
- Use `HStack` to align date picker with its checkbox

#### Numeric Inputs
- Provide sensible defaults (e.g., "1" for max uses)
- Include placeholder text or help text explaining units
- For optional fields, allow empty state for "unlimited" or similar
- **CRITICAL:** Never use `Decimal(string:)` for user-entered text — it silently truncates at commas (e.g., "1,500" → 1). Always use `Decimal.fromUserInput()` which strips grouping separators first.

#### Toggles
- Use for simple on/off states only
- Place toggle label on the left, control on the right
- Don't use toggles to show/hide entire sections

#### Buttons
- Use `ToolbarItem` for form actions in NavigationStack
- Cancel button: `placement: .cancellationAction`
- Primary button: `placement: .confirmationAction`
- Disable save/submit buttons when form is invalid: `.disabled(!isValid)`

#### Sections
- Use descriptive section headers
- Add footer text with `.font(.caption)` for additional context
- Keep sections focused on a single topic

#### Colors
- Use semantic colors: `.green` for success, `.blue` for info, `.orange` for warnings
- Use system colors: `Color(.controlBackgroundColor)` for backgrounds
- Keep opacity subtle: `.opacity(0.1)` for tinted backgrounds

### Form Validation

#### View Models
- Create a computed `isValid` property that checks all required fields
- Use `@Published` for all form fields
- Implement `loadData()` to populate when editing existing records
- Implement `create()` or `save()` to build the model object

#### Required Fields
- Disable save button when required fields are empty
- Check for valid type conversions using `Decimal.fromUserInput()` (never raw `Decimal(string:)`)
- Validate dependent field requirements

### Window Sizing

Standard form sizes:
- Simple forms (2-4 fields): `width: 400, height: 250-300`
- Medium forms (5-8 fields): `width: 450-500, height: 400-500`
- Complex forms (9+ fields): `width: 550-600, height: 600-700`

### Accessibility

- Provide `.help()` text for non-obvious fields
- Use proper semantic labels
- Ensure keyboard navigation works (tab through fields)

## Code Organization

### File Structure
- Keep views and their view models in the same file when tightly coupled
- Use `// MARK: -` comments to separate sections
- Group related forms (e.g., PointTypeFormView, EarningRuleFormView) near their parent view

### Naming Conventions
- Forms: `[Entity]FormView`
- View Models: `[Entity]FormViewModel` or `[View]ViewModel`
- Actions: `onSave`, `onCancel`, `onConfirm`
- State: `showing[Action][Entity]` (e.g., `showingAddCard`)

## Database Operations

### Table Naming Convention (CRITICAL)

**Always explicitly specify the database table name in every GRDB model.**

```swift
struct MyModel: Codable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "my_models"  // ⚠️ REQUIRED

    var id: UUID
    // ... rest of model
}
```

**Why:** GRDB defaults to using the Swift struct name as the table name. Our database schema uses `snake_case` (SQL convention), but Swift uses `PascalCase`. Without explicit declaration, GRDB will look for the wrong table name.

**Common mistakes:**
- ❌ No declaration → Runtime error: "no such table: EarningCap"
- ❌ `static let databaseTableName = "EarningCap"` → Still wrong! Use snake_case

**Examples:**
- ✅ `struct EarningCap` → `static let databaseTableName = "earning_caps"`
- ✅ `struct EarningRuleCap` → `static let databaseTableName = "earning_rule_caps"`
- ✅ `struct SpendOffer` → `static let databaseTableName = "spend_offers"`
- ✅ `struct Transaction` → `static let databaseTableName = "transactions"`

**Junction tables need this too:**
```swift
struct EarningRuleCap: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "earning_rule_caps"

    var earningRuleId: UUID
    var earningCapId: UUID
}
```

### Raw SQL Queries - Column Names

**CRITICAL:** When writing raw SQL queries with `db.execute(sql:)`, use the EXACT column names from your migration, NOT snake_case versions.

**Examples from migrations:**
```swift
// Migration creates:
t.column("earningRuleId", .text)  // camelCase
t.column("earningCapId", .text)   // camelCase

// SQL queries MUST match:
✅ "DELETE FROM earning_rule_caps WHERE earningCapId = ?"
❌ "DELETE FROM earning_rule_caps WHERE earning_cap_id = ?"  // WRONG!
```

**Why:** SQLite column names are case-sensitive and must match exactly as created in migrations. GRDB does NOT automatically convert between snake_case and camelCase in raw SQL.

### Thread Safety
- Use `@MainActor` for all view models that publish UI state
- Capture values before async closures to avoid reference issues:
  ```swift
  let cardId = card.id
  let data = try await db.read { db in
      // Use cardId here, not self.card.id
  }
  ```

### Queries
- Prefer fetching all records and filtering in Swift over complex GRDB filters
- This avoids compiler ambiguity and is clearer to read
- Cache fetched data in view model properties

### Error Handling
- Always use do-catch blocks for database operations
- Print errors to console: `print("Error: \(error)")`
- Consider showing user-friendly alerts for critical errors

## Date and Timezone Handling

### Critical Rule: Always Use Local Timezone for Date-Only Operations

When working with dates (without times), **always use the user's local timezone** to avoid off-by-one errors.

#### ❌ WRONG - Using UTC (causes timezone bugs):
```swift
// Parsing dates from API
let formatter = ISO8601DateFormatter()
formatter.formatOptions = [.withFullDate]  // Defaults to UTC!
let date = formatter.date(from: "2024-01-01")  // Will be off by a day in US timezones

// Formatting dates for API
let formatter = ISO8601DateFormatter()
formatter.formatOptions = [.withFullDate]
let dateString = formatter.string(from: date)  // Converts to UTC first!
```

#### ✅ CORRECT - Using local timezone:
```swift
// Parsing dates from API (e.g., YNAB's "2024-01-01" format)
let formatter = DateFormatter()
formatter.dateFormat = "yyyy-MM-dd"
formatter.timeZone = TimeZone.current  // Use user's timezone
let date = formatter.date(from: "2024-01-01")  // Correct local date

// Formatting dates for API
let formatter = DateFormatter()
formatter.dateFormat = "yyyy-MM-dd"
formatter.timeZone = TimeZone.current  // Use user's timezone
let dateString = formatter.string(from: date)  // "2024-01-01" in user's timezone
```

### Why This Matters

**Example of the bug:**
- User in EST (UTC-5) selects "January 1, 2024" in a DatePicker
- DatePicker stores: `2024-01-01 00:00:00 EST` (which is `2024-01-01 05:00:00 UTC`)
- ISO8601DateFormatter formats as: `"2024-01-01"` (extracting date in UTC)
- ✅ Correct behavior: Returns Jan 1st
- BUT if you parse "2024-01-01" with ISO8601DateFormatter:
  - It assumes UTC: `2024-01-01 00:00:00 UTC`
  - In EST: `2023-12-31 19:00:00 EST`
  - ❌ Displays as December 31st!

### When to Use Which Formatter

**DateFormatter with TimeZone.current:**
- ✅ Parsing/formatting dates from external APIs (YNAB, CSV files, etc.)
- ✅ Any date-only operation (no time component)
- ✅ When the "date" should match the user's calendar

**ISO8601DateFormatter:**
- ✅ Full timestamps with time zones (e.g., `2024-01-01T14:30:00Z`)
- ✅ When you need true UTC timestamps
- ❌ NOT for date-only strings like "2024-01-01"

### Common Patterns

**YNAB date parsing:**
```swift
let formatter = DateFormatter()
formatter.dateFormat = "yyyy-MM-dd"
formatter.timeZone = TimeZone.current
guard let date = formatter.date(from: ynabTx.date) else { return }
```

**YNAB date formatting (for API requests):**
```swift
let formatter = DateFormatter()
formatter.dateFormat = "yyyy-MM-dd"
formatter.timeZone = TimeZone.current
let dateString = formatter.string(from: selectedDate)
```

## Testing Workflow

Before committing changes:
1. Create a new card with all fields
2. Add point types and earning rules
3. Create a spend offer with all three types
4. Create rebates with various configurations
5. Create transactions and verify reward calculations
6. Test editing existing records
7. Verify navigation works (back buttons, sidebar switching)

## Common Patterns

### Optional Array Fields
When a field can be optional array (like `matchValues`):
- Use empty array `[]` for "all" or "none" cases
- Don't use `nil` for arrays in model structs
- In forms, use comma-separated strings and split:
  ```swift
  let array = string.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
  ```

### Enum Handling
- Always use camelCase for Swift enum cases (e.g., `.percentageBack`)
- Store as snake_case strings in database via raw values
- Display with: `rawValue.replacingOccurrences(of: "_", with: " ").capitalized`

### Default Values
- Provide sensible defaults in form view models
- Example: `maxUses = "1"`, `isActive = true`, `matchType = .allSpend`
- Initialize dates with reasonable defaults (e.g., 6 months from now for expiration)
