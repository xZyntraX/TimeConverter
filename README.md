# TimeConverter

A lightweight, immutable Luau module for creating, manipulating, and formatting durations, inspired by .NET's `TimeSpan`.

Built with `--!strict` typing and zero dependencies, it handles timers, cooldowns, match clocks, and timestamp differences without repeating manual `math.floor` and `string.format` math across your codebase.

## Installation

**Roblox Studio**
Download `TimeConverter.rbxm` from the Releases page—or copy `src/TimeConverter.luau` into a new `ModuleScript`—and place it in `ReplicatedStorage`.

**Rojo**
Drop `src/TimeConverter.luau` into your shared source directory (e.g., `src/shared/TimeConverter.luau`) and require it normally.

## Quick Start

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TimeConverter = require(ReplicatedStorage.TimeConverter)

local cooldown = TimeConverter.fromMinutes(2)
	:subtractSeconds(15)
	:clamp(TimeConverter.fromSeconds(0), TimeConverter.fromMinutes(5))

print(cooldown:format("%H:%m:%s.%f")) --> 00:01:45.000
print(cooldown:toShortString())       --> 1m 45s
print(cooldown:toLongString())        --> 1 minute, 45 seconds
print(cooldown:toISOString())         --> PT1M45S
```

## Design Notes

### Immutability
Every arithmetic or mode-switching method returns a new `TimeQuery` instance instead of mutating the original. You can safely keep shared constants (like max durations or thresholds) and always reassign when ticking a timer:

```lua
local base = TimeConverter.fromMinutes(1)
local extended = base:addSeconds(30)

print(base:toShortString())     --> 1m 0s
print(extended:toShortString()) --> 1m 30s
```

### Decomposed vs. Total Mode
Instances default to `formatTimer()`, which breaks a duration into individual calendar and clock components. Switching to `totalTimer()` converts the entire duration into whichever unit you read (floored):

```lua
local duration = TimeConverter.fromSeconds(90)

-- Decomposed (default)
print(duration:minutes(), duration:seconds()) --> 1  30

-- Total
local totals = duration:totalTimer()
print(totals:seconds())      --> 90
print(totals:milliseconds()) --> 90000
```

### Precision & Approximations
- Durations are stored internally as rounded integer milliseconds (`math.round`), avoiding common IEEE 754 float issues such as `0.1 + 0.2 ~= 0.3` in equality checks or truncated milliseconds in modulo math.
- All durations clamp at `0`; negative values do not underflow.
- Calendar decomposition uses fixed approximations: **1 month = 30 days** and **1 year = 365 days**.

## Examples

### Ability Cooldown
Using constants and Luau metamethods (`-`, `>`, `==`) to track a cooldown:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TimeConverter = require(ReplicatedStorage.TimeConverter)

local ZERO = TimeConverter.fromSeconds(0)
local BASE_COOLDOWN = TimeConverter.fromSeconds(12)
local HASTE_BONUS = TimeConverter.fromSeconds(3.5)

local remaining = BASE_COOLDOWN - HASTE_BONUS

while remaining > ZERO do
	print(remaining:format("%s.%f") .. "s")
	task.wait(0.5)
	remaining = remaining:subtractMilliseconds(500)
end

print("Ready")
```

### Match Countdown with Low-Time Threshold
Driving a `TextLabel` on `RenderStepped` with millisecond accuracy:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TimeConverter = require(ReplicatedStorage.TimeConverter)

local ZERO = TimeConverter.fromSeconds(0)
local WARNING_TIME = TimeConverter.fromSeconds(10)

local matchTimer = TimeConverter.fromClock(0, 2, 30)
local label = script.Parent :: TextLabel
local accumulator = 0

local connection
connection = RunService.RenderStepped:Connect(function(dt)
	accumulator += dt
	local ms = math.floor(accumulator * 1000)

	if ms > 0 then
		accumulator -= ms / 1000
		matchTimer = matchTimer:subtractMilliseconds(ms)
	end

	if matchTimer == ZERO then
		label.Text = "TIME UP"
		connection:Disconnect()
		return
	end

	if matchTimer < WARNING_TIME then
		label.TextColor3 = Color3.fromRGB(255, 80, 90)
		label.Text = matchTimer:format("%s.%f")
	else
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.Text = matchTimer:format("%m:%s")
	end
end)
```

### Daily Reward / Expiration (`os.time`)
Calculating remaining time from a saved Unix timestamp:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TimeConverter = require(ReplicatedStorage.TimeConverter)

local DAILY_INTERVAL = TimeConverter.fromHours(24)

local lastClaim = os.time() - 54321 -- e.g. loaded from DataStore
local elapsed = TimeConverter.fromSeconds(os.time() - lastClaim)

if elapsed >= DAILY_INTERVAL then
	print("Reward available")
else
	local remaining = DAILY_INTERVAL - elapsed
	print("Available in:", remaining:toLongString())
	print("Compact:", remaining:toShortString(true))
end
```

### Speedrun Split Comparison
Comparing a finished run against a personal best with `:compare()`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TimeConverter = require(ReplicatedStorage.TimeConverter)

local personalBest = TimeConverter.fromTable({ minutes = 1, seconds = 42, milliseconds = 350 })
local currentRun = TimeConverter.fromTable({ minutes = 1, seconds = 39, milliseconds = 820 })

local diff = currentRun:compare(personalBest)

if diff < 0 then
	local saved = personalBest - currentRun
	print("New PB: -" .. saved:format("%s.%f") .. "s") --> New PB: -02.530s
elseif diff > 0 then
	local behind = currentRun - personalBest
	print("Behind PB: +" .. behind:format("%s.%f") .. "s")
else
	print("Tied PB")
end
```

### Formatting Outputs

```lua
local t = TimeConverter.fromTable({
	days = 2,
	hours = 4,
	minutes = 5,
	seconds = 0,
	milliseconds = 250,
})

print(t:format("%D days %H:%m:%s.%f")) --> 02 days 04:05:00.250
print(t:toString())                   --> 00:00:00:02 04:05:00
print(t:toShortString())              --> 2d 4h 5m 0s
print(t:toShortString(true))          --> 2d 4h 5m
print(t:toLongString())               --> 2 days, 4 hours, 5 minutes
print(t:toISOString())                --> P2DT4H5M0.25S
```

## API Reference

### Constructors

| Method | Description |
| :--- | :--- |
| `fromMilliseconds(n)` ... `fromYears(n)` | Creates a duration from a single unit (`Milliseconds`, `Seconds`, `Minutes`, `Hours`, `Days`, `Weeks`, `Months`, `Years`). |
| `fromTable(input)` | Creates a duration from a `TimeInput` table (e.g., `{ hours = 1, minutes = 30 }`). Unknown keys throw an error. |
| `fromClock(h?, m?, s?, ms?)` | Shorthand for clock values. Omitted arguments default to `0`. |

### Modes & Getters

| Method | Returns | Description |
| :--- | :--- | :--- |
| `:formatTimer()` | `TimeQuery` | Returns a copy in decomposed mode (default). |
| `:totalTimer()` | `TimeQuery` | Returns a copy in total conversion mode. |
| `:milliseconds()` ... `:years()` | `number` | Reads a single unit (`milliseconds`, `seconds`, `minutes`, `hours`, `days`, `weeks`, `months`, `years`). |
| `:all()` | `8 numbers` | Returns `ms, s, m, h, d, w, mo, y` in a single call. |

### Arithmetic & Comparisons

| Method | Operator | Description |
| :--- | :---: | :--- |
| `:add(other)` / `:subtract(other)` | `+` / `-` | Adds or subtracts another `TimeQuery`. |
| `:addMilliseconds(n)` ... `:addYears(n)` | — | Adds a specific unit. |
| `:subtractMilliseconds(n)` ... `:subtractYears(n)` | — | Subtracts a specific unit (clamped at `0`). |
| `:multiply(factor)` / `:divide(divisor)` | — | Scales the duration. Dividing by `0` throws an error. |
| `:clamp(min, max)` | — | Clamps between `min` and `max`. Accepts `TimeQuery` or a `number` (in seconds). |
| `:equals(other)` | `==` | Exact millisecond equality check. |
| `:lessThan(other)` / `:lessThanOrEqual(other)` | `<` / `<=` | Ordering checks (`>` and `>=` also work via metamethods). |
| `:greaterThan(other)` / `:greaterThanOrEqual(other)` | `>` / `>=` | Ordering checks. |
| `:compare(other)` | — | Returns `-1`, `0`, or `1`. |

### Formatting

| Method | Description |
| :--- | :--- |
| `:format(pattern)` | Replaces `%Y`, `%M`, `%W`, `%D`, `%H`, `%m`, `%s` (2-digit) and `%f` (3-digit ms) using decomposed parts. |
| `:toString()` | Formats as `%Y:%M:%W:%D %H:%m:%s` (also wired to `__tostring`). |
| `:toShortString(removeZeroSeconds?)` | Compact output (`1h 5m 3s`). Pass `true` to hide `0s` when larger units are present. |
| `:toLongString()` | Full pluralized string (`1 hour, 5 minutes, 3 seconds`). |
| `:toISOString()` | ISO 8601 duration string (`P1DT2H30M5.25S`, or `PT0S` when zero). |

## Input Validation

All public methods validate their arguments and raise descriptive `[TimeConverter]` errors instead of failing silently:

- Non-number values, `NaN`, and `±math.huge` are rejected.
- `fromTable()` rejects unknown unit keys (catching typos like `{ second = 10 }`).
- `divide(0)` and `clamp(min, max)` where `min > max` throw immediately.
- Comparisons, `add()`, and `subtract()` verify that the passed object is a `TimeConverter` instance.

## License

MIT