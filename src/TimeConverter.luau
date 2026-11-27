--!strict
--[[
	Created by: Zyntra (lucasrtt132)
	Version: 1.6.0
	Last updated: 26/11/2026

	A lightweight and chainable time conversion library
	inspired by .NET TimeSpan.

	Notes:
	- Calendar decomposition uses fixed approximations: 1 month = 30 days, 1 year = 365 days.
	- Durations are clamped at 0 and stored internally as rounded integer milliseconds.

	Features:
	- Optionally removes zero seconds
	- Time conversion and decomposition
	- Mathematical operations and Luau metamethods (+, -, ==, <, <=, tostring)
	- Duration comparisons
	- Custom formatting and valid ISO 8601 output
	- Immutable operations
	- Strict input validation
]]

export type TimeInput = {
	milliseconds: number?,
	seconds: number?,
	minutes: number?,
	hours: number?,
	days: number?,
	weeks: number?,
	months: number?,
	years: number?,
}

export type TimeQuery = {
	formatTimer: (self: TimeQuery) -> TimeQuery,
	totalTimer: (self: TimeQuery) -> TimeQuery,

	milliseconds: (self: TimeQuery) -> number,
	seconds: (self: TimeQuery) -> number,
	minutes: (self: TimeQuery) -> number,
	hours: (self: TimeQuery) -> number,
	days: (self: TimeQuery) -> number,
	weeks: (self: TimeQuery) -> number,
	months: (self: TimeQuery) -> number,
	years: (self: TimeQuery) -> number,

	all: (self: TimeQuery) -> (
		number, number, number, number,
		number, number, number, number
	),

	add: (self: TimeQuery, other: TimeQuery) -> TimeQuery,
	addMilliseconds: (self: TimeQuery, value: number) -> TimeQuery,
	addSeconds: (self: TimeQuery, value: number) -> TimeQuery,
	addMinutes: (self: TimeQuery, value: number) -> TimeQuery,
	addHours: (self: TimeQuery, value: number) -> TimeQuery,
	addDays: (self: TimeQuery, value: number) -> TimeQuery,
	addWeeks: (self: TimeQuery, value: number) -> TimeQuery,
	addMonths: (self: TimeQuery, value: number) -> TimeQuery,
	addYears: (self: TimeQuery, value: number) -> TimeQuery,

	subtract: (self: TimeQuery, other: TimeQuery) -> TimeQuery,
	subtractMilliseconds: (self: TimeQuery, value: number) -> TimeQuery,
	subtractSeconds: (self: TimeQuery, value: number) -> TimeQuery,
	subtractMinutes: (self: TimeQuery, value: number) -> TimeQuery,
	subtractHours: (self: TimeQuery, value: number) -> TimeQuery,
	subtractDays: (self: TimeQuery, value: number) -> TimeQuery,
	subtractWeeks: (self: TimeQuery, value: number) -> TimeQuery,
	subtractMonths: (self: TimeQuery, value: number) -> TimeQuery,
	subtractYears: (self: TimeQuery, value: number) -> TimeQuery,

	multiply: (self: TimeQuery, value: number) -> TimeQuery,
	divide: (self: TimeQuery, value: number) -> TimeQuery,
	clamp: (self: TimeQuery, min: TimeQuery | number, max: TimeQuery | number) -> TimeQuery,

	equals: (self: TimeQuery, other: TimeQuery) -> boolean,
	greaterThan: (self: TimeQuery, other: TimeQuery) -> boolean,
	lessThan: (self: TimeQuery, other: TimeQuery) -> boolean,
	greaterThanOrEqual: (self: TimeQuery, other: TimeQuery) -> boolean,
	lessThanOrEqual: (self: TimeQuery, other: TimeQuery) -> boolean,
	compare: (self: TimeQuery, other: TimeQuery) -> number,

	format: (self: TimeQuery, pattern: string) -> string,
	toString: (self: TimeQuery) -> string,
	toShortString: (self: TimeQuery, removeZeroSeconds: boolean?) -> string,
	toLongString: (self: TimeQuery) -> string,
	toISOString: (self: TimeQuery) -> string,
}

export type TimeConverterModule = {
	fromMilliseconds: (value: number) -> TimeQuery,
	fromSeconds: (value: number) -> TimeQuery,
	fromMinutes: (value: number) -> TimeQuery,
	fromHours: (value: number) -> TimeQuery,
	fromDays: (value: number) -> TimeQuery,
	fromWeeks: (value: number) -> TimeQuery,
	fromMonths: (value: number) -> TimeQuery,
	fromYears: (value: number) -> TimeQuery,
	fromTable: (value: TimeInput) -> TimeQuery,
	fromClock: (
		hours: number?,
		minutes: number?,
		seconds: number?,
		milliseconds: number?
	) -> TimeQuery,
}

type TimerMethod = "format" | "total"

type TimeParts = {
	years: number,
	months: number,
	weeks: number,
	days: number,
	hours: number,
	minutes: number,
	seconds: number,
	milliseconds: number,
}

type InternalTimeQuery = TimeQuery & {
	_milliseconds: number,
	_method: TimerMethod,
}

local MS_PER_UNIT: { [string]: number } = table.freeze({
	milliseconds = 1,
	seconds = 1000,
	minutes = 60_000,
	hours = 3_600_000,
	days = 86_400_000,
	weeks = 604_800_000,
	months = 2_592_000_000,
	years = 31_536_000_000,
})

local UNIT_ORDER: { string } = table.freeze({
	"years",
	"months",
	"weeks",
	"days",
	"hours",
	"minutes",
	"seconds",
})

local SHORT_SUFFIXES: { [string]: string } = table.freeze({
	years = "y",
	months = "mo",
	weeks = "w",
	days = "d",
	hours = "h",
	minutes = "m",
	seconds = "s",
})

local LONG_NAMES: { [string]: string } = table.freeze({
	years = "year",
	months = "month",
	weeks = "week",
	days = "day",
	hours = "hour",
	minutes = "minute",
	seconds = "second",
	milliseconds = "millisecond",
})

local TimeConverter = {}
TimeConverter.__index = TimeConverter

local function validate(value: number, name: string): number
	assert(
		type(value) == "number"
			and value == value
			and value ~= math.huge
			and value ~= -math.huge,
		("[TimeConverter] Invalid %s value. Expected a finite number."):format(name)
	)

	return value
end

local function create(milliseconds: number, method: TimerMethod?): TimeQuery
	validate(milliseconds, "time")

	local normalized = math.round(math.max(0, milliseconds))

	return setmetatable({
		_milliseconds = normalized,
		_method = method or "format",
	}, TimeConverter) :: any
end

local function clone(self: InternalTimeQuery, milliseconds: number): TimeQuery
	return create(milliseconds, self._method)
end

local function getOtherMilliseconds(other: TimeQuery): number
	assert(
		type(other) == "table" and getmetatable(other :: any) == TimeConverter,
		"[TimeConverter] Expected another TimeConverter instance."
	)

	return (other :: InternalTimeQuery)._milliseconds
end

local function toMilliseconds(value: TimeQuery | number, name: string): number
	if type(value) == "table" then
		return getOtherMilliseconds(value)
	end

	return validate(value, name) * MS_PER_UNIT.seconds
end

local function getParts(self: InternalTimeQuery): TimeParts
	local totalMs = self._milliseconds
	local milliseconds = totalMs % 1000
	local totalSeconds = math.floor(totalMs / 1000)

	local totalDays = math.floor(totalSeconds / 86400)
	local remainingDays = totalDays

	local years = math.floor(remainingDays / 365)
	remainingDays %= 365

	local months = math.floor(remainingDays / 30)
	remainingDays %= 30

	local weeks = math.floor(remainingDays / 7)
	local days = remainingDays % 7

	local hours = math.floor(totalSeconds / 3600) % 24
	local minutes = math.floor(totalSeconds / 60) % 60
	local seconds = totalSeconds % 60

	return {
		years = years,
		months = months,
		weeks = weeks,
		days = days,
		hours = hours,
		minutes = minutes,
		seconds = seconds,
		milliseconds = milliseconds,
	}
end

local function getValue(self: InternalTimeQuery, unit: string): number
	if self._method == "total" then
		return math.floor(self._milliseconds / MS_PER_UNIT[unit])
	end

	return (getParts(self) :: { [string]: number })[unit]
end

local function formatUnit(value: number, unit: string): string
	local name = LONG_NAMES[unit]

	return ("%d %s%s"):format(
		value,
		name,
		if value == 1 then "" else "s"
	)
end

-- Inputs
function TimeConverter.fromMilliseconds(value: number): TimeQuery
	return create(validate(value, "milliseconds"))
end

function TimeConverter.fromSeconds(value: number): TimeQuery
	return create(validate(value, "seconds") * MS_PER_UNIT.seconds)
end

function TimeConverter.fromMinutes(value: number): TimeQuery
	return create(validate(value, "minutes") * MS_PER_UNIT.minutes)
end

function TimeConverter.fromHours(value: number): TimeQuery
	return create(validate(value, "hours") * MS_PER_UNIT.hours)
end

function TimeConverter.fromDays(value: number): TimeQuery
	return create(validate(value, "days") * MS_PER_UNIT.days)
end

function TimeConverter.fromWeeks(value: number): TimeQuery
	return create(validate(value, "weeks") * MS_PER_UNIT.weeks)
end

function TimeConverter.fromMonths(value: number): TimeQuery
	return create(validate(value, "months") * MS_PER_UNIT.months)
end

function TimeConverter.fromYears(value: number): TimeQuery
	return create(validate(value, "years") * MS_PER_UNIT.years)
end

function TimeConverter.fromTable(value: TimeInput): TimeQuery
	assert(type(value) == "table", "[TimeConverter] Expected a table.")

	local milliseconds = 0

	for unit, amount in pairs(value :: { [string]: any }) do
		local multiplier = MS_PER_UNIT[unit]
		assert(
			multiplier ~= nil,
			("[TimeConverter] Unknown time unit '%s'."):format(tostring(unit))
		)

		milliseconds += validate(amount, unit) * multiplier
	end

	return create(milliseconds)
end

function TimeConverter.fromClock(
	hours: number?,
	minutes: number?,
	seconds: number?,
	milliseconds: number?
): TimeQuery
	return TimeConverter.fromTable({
		hours = hours or 0,
		minutes = minutes or 0,
		seconds = seconds or 0,
		milliseconds = milliseconds or 0,
	})
end

-- Methods
function TimeConverter:formatTimer(): TimeQuery
	return create((self :: InternalTimeQuery)._milliseconds, "format")
end

function TimeConverter:totalTimer(): TimeQuery
	return create((self :: InternalTimeQuery)._milliseconds, "total")
end

-- Conversions
function TimeConverter:milliseconds(): number
	return getValue(self :: InternalTimeQuery, "milliseconds")
end

function TimeConverter:seconds(): number
	return getValue(self :: InternalTimeQuery, "seconds")
end

function TimeConverter:minutes(): number
	return getValue(self :: InternalTimeQuery, "minutes")
end

function TimeConverter:hours(): number
	return getValue(self :: InternalTimeQuery, "hours")
end

function TimeConverter:days(): number
	return getValue(self :: InternalTimeQuery, "days")
end

function TimeConverter:weeks(): number
	return getValue(self :: InternalTimeQuery, "weeks")
end

function TimeConverter:months(): number
	return getValue(self :: InternalTimeQuery, "months")
end

function TimeConverter:years(): number
	return getValue(self :: InternalTimeQuery, "years")
end

function TimeConverter:all(): (
	number, number, number, number,
	number, number, number, number
)
	local internal = self :: InternalTimeQuery

	if internal._method == "total" then
		local ms = internal._milliseconds
		return ms,
			math.floor(ms / MS_PER_UNIT.seconds),
			math.floor(ms / MS_PER_UNIT.minutes),
			math.floor(ms / MS_PER_UNIT.hours),
			math.floor(ms / MS_PER_UNIT.days),
			math.floor(ms / MS_PER_UNIT.weeks),
			math.floor(ms / MS_PER_UNIT.months),
			math.floor(ms / MS_PER_UNIT.years)
	end

	local parts = getParts(internal)
	return parts.milliseconds,
		parts.seconds,
		parts.minutes,
		parts.hours,
		parts.days,
		parts.weeks,
		parts.months,
		parts.years
end

-- Mathematical operations
function TimeConverter:add(other: TimeQuery): TimeQuery
	local internal = self :: InternalTimeQuery
	return clone(internal, internal._milliseconds + getOtherMilliseconds(other))
end

function TimeConverter:addMilliseconds(value: number): TimeQuery
	local internal = self :: InternalTimeQuery
	return clone(internal, internal._milliseconds + validate(value, "milliseconds"))
end

function TimeConverter:addSeconds(value: number): TimeQuery
	local internal = self :: InternalTimeQuery
	return clone(internal, internal._milliseconds + validate(value, "seconds") * MS_PER_UNIT.seconds)
end

function TimeConverter:addMinutes(value: number): TimeQuery
	local internal = self :: InternalTimeQuery
	return clone(internal, internal._milliseconds + validate(value, "minutes") * MS_PER_UNIT.minutes)
end

function TimeConverter:addHours(value: number): TimeQuery
	local internal = self :: InternalTimeQuery
	return clone(internal, internal._milliseconds + validate(value, "hours") * MS_PER_UNIT.hours)
end

function TimeConverter:addDays(value: number): TimeQuery
	local internal = self :: InternalTimeQuery
	return clone(internal, internal._milliseconds + validate(value, "days") * MS_PER_UNIT.days)
end

function TimeConverter:addWeeks(value: number): TimeQuery
	local internal = self :: InternalTimeQuery
	return clone(internal, internal._milliseconds + validate(value, "weeks") * MS_PER_UNIT.weeks)
end

function TimeConverter:addMonths(value: number): TimeQuery
	local internal = self :: InternalTimeQuery
	return clone(internal, internal._milliseconds + validate(value, "months") * MS_PER_UNIT.months)
end

function TimeConverter:addYears(value: number): TimeQuery
	local internal = self :: InternalTimeQuery
	return clone(internal, internal._milliseconds + validate(value, "years") * MS_PER_UNIT.years)
end

function TimeConverter:subtract(other: TimeQuery): TimeQuery
	local internal = self :: InternalTimeQuery
	return clone(internal, internal._milliseconds - getOtherMilliseconds(other))
end

function TimeConverter:subtractMilliseconds(value: number): TimeQuery
	local internal = self :: InternalTimeQuery
	return clone(internal, internal._milliseconds - validate(value, "milliseconds"))
end

function TimeConverter:subtractSeconds(value: number): TimeQuery
	local internal = self :: InternalTimeQuery
	return clone(internal, internal._milliseconds - validate(value, "seconds") * MS_PER_UNIT.seconds)
end

function TimeConverter:subtractMinutes(value: number): TimeQuery
	local internal = self :: InternalTimeQuery
	return clone(internal, internal._milliseconds - validate(value, "minutes") * MS_PER_UNIT.minutes)
end

function TimeConverter:subtractHours(value: number): TimeQuery
	local internal = self :: InternalTimeQuery
	return clone(internal, internal._milliseconds - validate(value, "hours") * MS_PER_UNIT.hours)
end

function TimeConverter:subtractDays(value: number): TimeQuery
	local internal = self :: InternalTimeQuery
	return clone(internal, internal._milliseconds - validate(value, "days") * MS_PER_UNIT.days)
end

function TimeConverter:subtractWeeks(value: number): TimeQuery
	local internal = self :: InternalTimeQuery
	return clone(internal, internal._milliseconds - validate(value, "weeks") * MS_PER_UNIT.weeks)
end

function TimeConverter:subtractMonths(value: number): TimeQuery
	local internal = self :: InternalTimeQuery
	return clone(internal, internal._milliseconds - validate(value, "months") * MS_PER_UNIT.months)
end

function TimeConverter:subtractYears(value: number): TimeQuery
	local internal = self :: InternalTimeQuery
	return clone(internal, internal._milliseconds - validate(value, "years") * MS_PER_UNIT.years)
end

function TimeConverter:multiply(value: number): TimeQuery
	local internal = self :: InternalTimeQuery
	return clone(internal, internal._milliseconds * validate(value, "multiplier"))
end

function TimeConverter:divide(value: number): TimeQuery
	local internal = self :: InternalTimeQuery
	value = validate(value, "divisor")

	assert(value ~= 0, "[TimeConverter] Cannot divide by zero.")

	return clone(internal, internal._milliseconds / value)
end

function TimeConverter:clamp(min: TimeQuery | number, max: TimeQuery | number): TimeQuery
	local internal = self :: InternalTimeQuery
	local minMs = toMilliseconds(min, "minimum")
	local maxMs = toMilliseconds(max, "maximum")

	assert(minMs <= maxMs, "[TimeConverter] Minimum cannot exceed maximum.")

	return clone(internal, math.clamp(internal._milliseconds, minMs, maxMs))
end

-- Comparisons
function TimeConverter:equals(other: TimeQuery): boolean
	return (self :: InternalTimeQuery)._milliseconds == getOtherMilliseconds(other)
end

function TimeConverter:greaterThan(other: TimeQuery): boolean
	return (self :: InternalTimeQuery)._milliseconds > getOtherMilliseconds(other)
end

function TimeConverter:lessThan(other: TimeQuery): boolean
	return (self :: InternalTimeQuery)._milliseconds < getOtherMilliseconds(other)
end

function TimeConverter:greaterThanOrEqual(other: TimeQuery): boolean
	return (self :: InternalTimeQuery)._milliseconds >= getOtherMilliseconds(other)
end

function TimeConverter:lessThanOrEqual(other: TimeQuery): boolean
	return (self :: InternalTimeQuery)._milliseconds <= getOtherMilliseconds(other)
end

function TimeConverter:compare(other: TimeQuery): number
	local first = (self :: InternalTimeQuery)._milliseconds
	local second = getOtherMilliseconds(other)

	if first < second then
		return -1
	elseif first > second then
		return 1
	end

	return 0
end

-- Formatting
function TimeConverter:format(pattern: string): string
	assert(type(pattern) == "string", "[TimeConverter] Expected a format string.")

	local parts = getParts(self :: InternalTimeQuery)
	local values: { [string]: number } = {
		Y = parts.years,
		M = parts.months,
		W = parts.weeks,
		D = parts.days,
		H = parts.hours,
		m = parts.minutes,
		s = parts.seconds,
		f = parts.milliseconds,
	}

	return (string.gsub(pattern, "%%([YMWDHmsf])", function(token)
		local value = values[token]
		return string.format(if token == "f" then "%03d" else "%02d", value)
	end))
end

function TimeConverter:toString(): string
	return self:format("%Y:%M:%W:%D %H:%m:%s")
end

function TimeConverter:toShortString(removeZeroSeconds: boolean?): string
	local hideZeroSeconds = if removeZeroSeconds == nil then false else removeZeroSeconds
	local parts = getParts(self :: InternalTimeQuery)
	local result = {}

	for _, unit in ipairs(UNIT_ORDER) do
		local value = (parts :: { [string]: number })[unit]

		if value > 0 or (unit == "seconds" and not hideZeroSeconds) then
			table.insert(result, string.format("%d%s", value, SHORT_SUFFIXES[unit]))
		end
	end

	return if #result > 0 then table.concat(result, " ") else "0s"
end

function TimeConverter:toLongString(): string
	local parts = getParts(self :: InternalTimeQuery)
	local result = {}

	for _, unit in ipairs(UNIT_ORDER) do
		local value = (parts :: { [string]: number })[unit]

		if value > 0 then
			table.insert(result, formatUnit(value, unit))
		end
	end

	return if #result > 0 then table.concat(result, ", ") else "0 seconds"
end

function TimeConverter:toISOString(): string
	local parts = getParts(self :: InternalTimeQuery)
	local date = ""

	if parts.years > 0 then
		date ..= tostring(parts.years) .. "Y"
	end

	if parts.months > 0 then
		date ..= tostring(parts.months) .. "M"
	end

	local totalDays = (parts.weeks * 7) + parts.days
	if totalDays > 0 then
		date ..= tostring(totalDays) .. "D"
	end

	local time = ""

	if parts.hours > 0 then
		time ..= tostring(parts.hours) .. "H"
	end

	if parts.minutes > 0 then
		time ..= tostring(parts.minutes) .. "M"
	end

	if parts.seconds > 0 or parts.milliseconds > 0 then
		if parts.milliseconds > 0 then
			local frac = string.format("%03d", parts.milliseconds):gsub("0+$", "")
			time ..= string.format("%d.%sS", parts.seconds, frac)
		else
			time ..= tostring(parts.seconds) .. "S"
		end
	end

	if time ~= "" then
		return "P" .. date .. "T" .. time
	end

	return if date ~= "" then "P" .. date else "PT0S"
end

-- Metamethods
TimeConverter.__tostring = TimeConverter.toString
TimeConverter.__eq = TimeConverter.equals
TimeConverter.__lt = TimeConverter.lessThan
TimeConverter.__le = TimeConverter.lessThanOrEqual
TimeConverter.__add = TimeConverter.add
TimeConverter.__sub = TimeConverter.subtract

return (TimeConverter :: any) :: TimeConverterModule