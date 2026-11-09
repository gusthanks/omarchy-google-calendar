// Unit tests for the pure helpers in Model.js, run against the real module.
// Ported from the vitest suite that lived only in the installed copy
// (Model.test.js, which tested copies of these functions): same cases, now on
// node's built-in runner, no node_modules needed.
// Run with: node --test dev/tests/test_model_units.js

const { describe, it } = require("node:test");
const assert = require("node:assert/strict");
const Model = require("../../Model.js");

// The handful of vitest matchers the suite uses, on top of node:assert.
function expect(actual) {
  const m = {
    toBe: (v) => assert.strictEqual(actual, v),
    toEqual: (v) => assert.deepStrictEqual(actual, v),
    toBeNull: () => assert.strictEqual(actual, null),
    toContain: (v) => assert.ok(actual.includes(v), `${JSON.stringify(actual)} should contain ${JSON.stringify(v)}`),
    toHaveLength: (n) => assert.strictEqual(actual.length, n),
    toBeGreaterThanOrEqual: (n) => assert.ok(actual >= n, `${actual} >= ${n}`),
    toBeLessThan: (n) => assert.ok(actual < n, `${actual} < ${n}`),
  };
  m.not = { toBeNull: () => assert.notStrictEqual(actual, null) };
  return m;
}

const {
  pad2, dateKey, keyForDate, parseDateKey, daysInMonth, clampDay, coerceWeekStart,
  normalizedWeekStart, weekdayOrder, isoWeek, dayOfYear, daysInYear, yearProgress,
  yearProgressPercent, parseBirthYear, ageFromBirthYear, parseAge, parseLifeExpectancy,
  lifeProgress, lifeProgressPercent, neutralizeMarkup, sanitizeHexColor, sanitizeHttpsUrl,
  parseMinutes, formatMinutes, clockNeedsSeconds, clockFormats, clockFormatRing, nextClockFormat,
} = Model;

const DEFAULT_EVENT_COLOR = "#039be5"; // Model.js default for events without a valid color

describe('gusthx.google-calendar Model.js', () => {
  describe('pad2', () => {
    it('pads single digits', () => {
      expect(pad2(0)).toBe('00')
      expect(pad2(5)).toBe('05')
      expect(pad2(9)).toBe('09')
    })
    it('does not pad double digits', () => {
      expect(pad2(10)).toBe('10')
      expect(pad2(99)).toBe('99')
    })
  })

  describe('dateKey', () => {
    it('formats YYYY-MM-DD correctly', () => {
      expect(dateKey(2024, 0, 1)).toBe('2024-01-01')
      expect(dateKey(2024, 11, 31)).toBe('2024-12-31')
      expect(dateKey(2024, 5, 15)).toBe('2024-06-15')
    })
  })

  describe('parseDateKey', () => {
    it('parses valid keys', () => {
      const r = parseDateKey('2024-06-15')
      expect(r).toEqual({ year: 2024, month: 5, day: 15, weekday: 6, key: '2024-06-15' })
    })
    it('returns null for invalid', () => {
      expect(parseDateKey('2024-13-01')).toBeNull()
      expect(parseDateKey('2024-00-01')).toBeNull()
      expect(parseDateKey('2024-06-32')).toBeNull()
      expect(parseDateKey('invalid')).toBeNull()
      expect(parseDateKey('')).toBeNull()
      expect(parseDateKey(null)).toBeNull()
    })
    it('validates actual dates (e.g. Feb 30)', () => {
      expect(parseDateKey('2024-02-30')).toBeNull()
      expect(parseDateKey('2023-02-29')).toBeNull()
      expect(parseDateKey('2024-02-29')).not.toBeNull() // leap year
    })
  })

  describe('daysInMonth', () => {
    it('returns correct days', () => {
      expect(daysInMonth(2024, 0)).toBe(31)
      expect(daysInMonth(2024, 1)).toBe(29) // leap
      expect(daysInMonth(2023, 1)).toBe(28)
      expect(daysInMonth(2024, 3)).toBe(30)
      expect(daysInMonth(2024, 11)).toBe(31)
    })
  })

  describe('clampDay', () => {
    it('clamps to valid range', () => {
      expect(clampDay(2024, 1, 0)).toBe(1)
      expect(clampDay(2024, 1, 30)).toBe(29)
      expect(clampDay(2024, 1, 15)).toBe(15)
    })
  })

  describe('coerceWeekStart', () => {
    it('accepts numbers 0-6', () => {
      expect(coerceWeekStart(0)).toBe(0)
      expect(coerceWeekStart(6)).toBe(6)
      expect(coerceWeekStart(7)).toBe(0)
      expect(coerceWeekStart(-1)).toBe(6)
    })
    it('accepts weekday names', () => {
      expect(coerceWeekStart('sunday')).toBe(0)
      expect(coerceWeekStart('monday')).toBe(1)
      expect(coerceWeekStart('saturday')).toBe(6)
      expect(coerceWeekStart('sun')).toBe(0)
      expect(coerceWeekStart('mon')).toBe(1)
    })
    it('accepts string numbers', () => {
      expect(coerceWeekStart('3')).toBe(3)
    })
    it('returns null for invalid', () => {
      expect(coerceWeekStart('')).toBeNull()
      expect(coerceWeekStart(null)).toBeNull()
      expect(coerceWeekStart(undefined)).toBeNull()
      expect(coerceWeekStart('invalid')).toBeNull()
    })
  })

  describe('normalizedWeekStart', () => {
    it('uses configured when valid', () => {
      expect(normalizedWeekStart(0, 1)).toBe(0)
      expect(normalizedWeekStart('monday', 1)).toBe(1)
    })
    it('falls back when configured invalid', () => {
      expect(normalizedWeekStart(null, 1)).toBe(1)
      expect(normalizedWeekStart('invalid', 0)).toBe(0)
    })
    it('defaults to Monday (1) when both invalid', () => {
      expect(normalizedWeekStart(null, null)).toBe(1)
      expect(normalizedWeekStart('invalid', 'invalid')).toBe(1)
    })
  })

  describe('weekdayOrder', () => {
    it('returns correct order for Monday start', () => {
      expect(weekdayOrder(1)).toEqual([1, 2, 3, 4, 5, 6, 0])
    })
    it('returns correct order for Sunday start', () => {
      expect(weekdayOrder(0)).toEqual([0, 1, 2, 3, 4, 5, 6])
    })
    it('returns correct order for Wednesday start', () => {
      expect(weekdayOrder(3)).toEqual([3, 4, 5, 6, 0, 1, 2])
    })
  })

  describe('isoWeek', () => {
    it('calculates ISO week numbers', () => {
      // Jan 1 2024 is Monday, week 1
      expect(isoWeek(2024, 0, 1)).toBe(1)
      // Dec 31 2023 is Sunday, week 52 of 2023
      expect(isoWeek(2023, 11, 31)).toBe(52)
      // Known dates
      expect(isoWeek(2024, 5, 15)).toBe(24) // June 15 2024
    })
  })

  describe('dayOfYear / daysInYear / yearProgress', () => {
    it('calculates day of year', () => {
      expect(dayOfYear(2024, 0, 1)).toBe(1)
      expect(dayOfYear(2024, 11, 31)).toBe(366) // leap
      expect(dayOfYear(2023, 11, 31)).toBe(365)
    })
    it('calculates days in year', () => {
      expect(daysInYear(2024)).toBe(366)
      expect(daysInYear(2023)).toBe(365)
    })
    it('calculates year progress', () => {
      expect(yearProgress(2024, 0, 1)).toBe(0) // Jan 1
      expect(yearProgressPercent(2024, 0, 1)).toBe(0)
      expect(yearProgressPercent(2024, 11, 31)).toBe(100) // Dec 31
      // Mid-year approx: June 15 in leap year = day 167/366 = 45.6% -> 45%
      const mid = yearProgressPercent(2024, 5, 15) // June 15
      expect(mid).toBeGreaterThanOrEqual(45)
      expect(mid).toBeLessThan(50)
    })
  })

  describe('parseBirthYear / ageFromBirthYear', () => {
    it('parses valid birth years', () => {
      expect(parseBirthYear('1990', 2024)).toBe(1990)
      expect(ageFromBirthYear('1990', 2024)).toBe(34)
    })
    it('rejects future years', () => {
      expect(parseBirthYear('2025', 2024)).toBe(0)
    })
    it('rejects too old', () => {
      expect(parseBirthYear('1800', 2024)).toBe(0)
    })
    it('rejects invalid format', () => {
      expect(parseBirthYear('90', 2024)).toBe(0)
      expect(parseBirthYear('abcd', 2024)).toBe(0)
    })
  })

  describe('parseAge / parseLifeExpectancy', () => {
    it('parses valid ages', () => {
      expect(parseAge('30')).toBe(30)
      expect(parseAge('120')).toBe(120)
    })
    it('rejects invalid', () => {
      expect(parseAge('0')).toBe(0)
      expect(parseAge('121')).toBe(0)
      expect(parseAge('abc')).toBe(0)
      expect(parseAge('')).toBe(0)
    })
    it('parseLifeExpectancy defaults to 90', () => {
      expect(parseLifeExpectancy('')).toBe(90)
      expect(parseLifeExpectancy('invalid')).toBe(90)
      expect(parseLifeExpectancy('80')).toBe(80)
    })
  })

  describe('lifeProgress', () => {
    it('calculates progress', () => {
      expect(lifeProgress(45, 90)).toBe(0.5)
      expect(lifeProgressPercent(45, 90)).toBe(50)
      expect(lifeProgress(0, 90)).toBe(0)
      expect(lifeProgress(90, 90)).toBe(1)
    })
    it('clamps to 0-1', () => {
      expect(lifeProgress(100, 90)).toBe(1)
      expect(lifeProgress(-10, 90)).toBe(0)
    })
  })

  describe('neutralizeMarkup', () => {
    it('strips control chars', () => {
      expect(neutralizeMarkup('test\x00\x1f')).toBe('test')
    })
    it('strips HTML tags', () => {
      expect(neutralizeMarkup('<script>alert(1)</script>')).toBe('alert(1)')
      expect(neutralizeMarkup('<b>bold</b>')).toBe('bold')
    })
    it('replaces angle brackets', () => {
      expect(neutralizeMarkup('a < b > c')).toBe('a ‹ b › c')
    })
    it('truncates to maxLen', () => {
      expect(neutralizeMarkup('a'.repeat(300), 100)).toHaveLength(100)
      expect(neutralizeMarkup('a'.repeat(300), 100).endsWith('…')).toBe(true)
    })
    it('handles empty/null', () => {
      expect(neutralizeMarkup('', 10)).toBe('')
      expect(neutralizeMarkup(null, 10)).toBe('')
    })
  })

  describe('sanitizeHexColor', () => {
    it('accepts valid hex', () => {
      expect(sanitizeHexColor('#ff0000')).toBe('#ff0000')
      expect(sanitizeHexColor('#ABCDEF')).toBe('#abcdef')
      expect(sanitizeHexColor('  #123456  ')).toBe('#123456')
    })
    it('rejects invalid', () => {
      expect(sanitizeHexColor('red')).toBe(DEFAULT_EVENT_COLOR)
      expect(sanitizeHexColor('#ff00')).toBe(DEFAULT_EVENT_COLOR)
      expect(sanitizeHexColor('#gggggg')).toBe(DEFAULT_EVENT_COLOR)
      expect(sanitizeHexColor('')).toBe(DEFAULT_EVENT_COLOR)
    })
    it('uses custom fallback', () => {
      expect(sanitizeHexColor('invalid', '#111111')).toBe('#111111')
    })
  })

  describe('sanitizeHttpsUrl', () => {
    it('accepts valid https', () => {
      expect(sanitizeHttpsUrl('https://example.com')).toBe('https://example.com')
      expect(sanitizeHttpsUrl('  https://example.com/path?query=1  ')).toBe('https://example.com/path?query=1')
    })
    it('rejects non-https', () => {
      expect(sanitizeHttpsUrl('http://example.com')).toBe('')
      expect(sanitizeHttpsUrl('ftp://example.com')).toBe('')
      expect(sanitizeHttpsUrl('example.com')).toBe('')
    })
    it('rejects dangerous chars', () => {
      expect(sanitizeHttpsUrl('https://example.com/<script>')).toBe('')
      expect(sanitizeHttpsUrl('https://example.com/"')).toBe('')
    })
    it('rejects too long', () => {
      expect(sanitizeHttpsUrl('https://' + 'a'.repeat(500))).toBe('')
    })
  })

  describe('parseMinutes / formatMinutes', () => {
    it('parses HH:MM', () => {
      expect(parseMinutes('00:00')).toBe(0)
      expect(parseMinutes('12:30')).toBe(750)
      expect(parseMinutes('23:59')).toBe(1439)
    })
    it('rejects invalid', () => {
      expect(parseMinutes('24:00')).toBe(-1)
      expect(parseMinutes('12:60')).toBe(-1)
      expect(parseMinutes('abc')).toBe(-1)
    })
    it('formats minutes back', () => {
      expect(formatMinutes(0)).toBe('00:00')
      expect(formatMinutes(750)).toBe('12:30')
      expect(formatMinutes(1439)).toBe('23:59')
    })
    it('clamps', () => {
      expect(formatMinutes(-10)).toBe('00:00')
      expect(formatMinutes(2000)).toBe('23:59')
    })
  })

  describe('clockNeedsSeconds', () => {
    it('detects seconds in format', () => {
      expect(clockNeedsSeconds('HH:mm:ss')).toBe(true)
      expect(clockNeedsSeconds('hh:mm:ss')).toBe(true)
      expect(clockNeedsSeconds('HH:mm')).toBe(false)
      expect(clockNeedsSeconds('h:mm AP')).toBe(false)
    })
    it('ignores quoted literal s', () => {
      expect(clockNeedsSeconds("'seconds: 'HH:mm")).toBe(false)
      expect(clockNeedsSeconds("'s'HH:mm")).toBe(false)
    })
  })

  describe('clockFormats', () => {
    it('returns horizontal formats by default', () => {
      const fmts = clockFormats(false)
      expect(fmts).toContain('dddd HH:mm')
      expect(fmts).toContain('HH:mm')
    })
    it('returns vertical formats when requested', () => {
      const fmts = clockFormats(true)
      expect(fmts).toContain('HH\n—\nmm')
      expect(fmts).toContain('HH\nmm')
    })
  })

  describe('clockFormatRing', () => {
    it('builds ring from presets + configured', () => {
      const ring = clockFormatRing('HH:mm', 'hh:mm AP', ['HH:mm:ss'])
      expect(ring).toEqual(['HH:mm:ss', 'hh:mm AP', 'HH:mm'])
    })
    it('deduplicates', () => {
      const ring = clockFormatRing('HH:mm', 'HH:mm', ['HH:mm'])
      expect(ring).toEqual(['HH:mm'])
    })
    it('falls back to default', () => {
      expect(clockFormatRing('', '', [])).toEqual(['HH:mm'])
    })
  })

  describe('nextClockFormat', () => {
    it('cycles through ring', () => {
      const ring = ['HH:mm', 'hh:mm AP', 'HH:mm:ss']
      expect(nextClockFormat(ring, 'HH:mm')).toBe('hh:mm AP')
      expect(nextClockFormat(ring, 'hh:mm AP')).toBe('HH:mm:ss')
      expect(nextClockFormat(ring, 'HH:mm:ss')).toBe('HH:mm')
    })
    it('handles missing current', () => {
      const ring = ['HH:mm', 'hh:mm AP']
      expect(nextClockFormat(ring, 'unknown')).toBe('HH:mm')
      expect(nextClockFormat(ring, '')).toBe('HH:mm')
    })
  })
})