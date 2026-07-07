import type { BookCard } from '@bookorbit/types'

export type SeriesBookAttribute = 'genres' | 'tags'

export type SeriesBookAttributeGroup = {
  key: string
  label: string
  books: BookCard[]
}

// Stable key for the bucket holding books that have no value for the attribute.
export const SERIES_ATTRIBUTE_UNGROUPED_KEY = '__ungrouped__'

const UNGROUPED_LABELS: Record<SeriesBookAttribute, string> = {
  genres: 'No genre',
  tags: 'No tags',
}

/**
 * Group series books by a multi-valued attribute (genres or tags). A book with
 * several values appears in each matching group; books with no values fall into a
 * single trailing "No genre"/"No tags" bucket. Named groups are sorted
 * alphabetically (case-insensitive); the ungrouped bucket is always last.
 */
export function groupSeriesBooksByAttribute(books: BookCard[], attribute: SeriesBookAttribute): SeriesBookAttributeGroup[] {
  const grouped = new Map<string, { label: string; books: BookCard[] }>()
  const ungrouped: BookCard[] = []

  for (const book of books) {
    const values = book[attribute] ?? []
    const seen = new Set<string>()
    let added = false

    for (const raw of values) {
      const label = raw.trim()
      if (!label) continue
      const key = label.toLowerCase()
      if (seen.has(key)) continue
      seen.add(key)
      added = true

      let entry = grouped.get(key)
      if (!entry) {
        entry = { label, books: [] }
        grouped.set(key, entry)
      }
      entry.books.push(book)
    }

    if (!added) ungrouped.push(book)
  }

  const groups: SeriesBookAttributeGroup[] = [...grouped.entries()]
    .sort((a, b) => a[1].label.localeCompare(b[1].label, undefined, { sensitivity: 'base' }))
    .map(([key, entry]) => ({ key, label: entry.label, books: entry.books }))

  if (ungrouped.length > 0) {
    groups.push({ key: SERIES_ATTRIBUTE_UNGROUPED_KEY, label: UNGROUPED_LABELS[attribute], books: ungrouped })
  }

  return groups
}
