import { describe, expect, it } from 'vitest'
import type { BookCard } from '@bookorbit/types'
import { groupSeriesBooksByAttribute, SERIES_ATTRIBUTE_UNGROUPED_KEY } from './useSeriesBookAttributeGroups'

function makeBook(overrides: Partial<BookCard> = {}): BookCard {
  return {
    id: 1,
    status: 'present',
    title: 'Series Book',
    authors: [],
    seriesId: 42,
    seriesName: 'The Series',
    seriesIndex: 1,
    files: [],
    publishedYear: null,
    language: null,
    genres: [],
    tags: [],
    rating: null,
    readingProgress: null,
    readStatus: null,
    addedAt: '2026-01-01T00:00:00.000Z',
    updatedAt: null,
    metadataScore: null,
    hasCover: false,
    hasMetadataLocks: false,
    lockedFields: [],
    subtitle: null,
    publisher: null,
    pageCount: null,
    isbn13: null,
    narrators: [],
    customMetadata: [],
    ...overrides,
  }
}

describe('groupSeriesBooksByAttribute', () => {
  it('fans a multi-genre book into each genre group', () => {
    const books = [makeBook({ id: 1, genres: ['Core Rules', 'Adventure'] }), makeBook({ id: 2, genres: ['Core Rules'] })]

    expect(groupSeriesBooksByAttribute(books, 'genres').map((g) => [g.label, g.books.map((b) => b.id)])).toEqual([
      ['Adventure', [1]],
      ['Core Rules', [1, 2]],
    ])
  })

  it('sorts named groups alphabetically and puts the ungrouped bucket last', () => {
    const books = [makeBook({ id: 1, genres: ['Zines'] }), makeBook({ id: 2, genres: [] }), makeBook({ id: 3, genres: ['Adventure'] })]

    const groups = groupSeriesBooksByAttribute(books, 'genres')
    expect(groups.map((g) => g.key)).toEqual(['adventure', 'zines', SERIES_ATTRIBUTE_UNGROUPED_KEY])
    expect(groups.at(-1)).toMatchObject({ key: SERIES_ATTRIBUTE_UNGROUPED_KEY, label: 'No genre', books: [books[1]] })
  })

  it('treats genre values case-insensitively and de-duplicates within a book', () => {
    const books = [makeBook({ id: 1, genres: ['Core Rules', 'core rules'] }), makeBook({ id: 2, genres: ['CORE RULES'] })]

    const groups = groupSeriesBooksByAttribute(books, 'genres')
    expect(groups).toHaveLength(1)
    expect(groups[0]).toMatchObject({ key: 'core rules', label: 'Core Rules' })
    expect(groups[0].books.map((b) => b.id)).toEqual([1, 2])
  })

  it('ignores blank values and labels the tag bucket "No tags"', () => {
    const books = [makeBook({ id: 1, tags: ['  ', ''] }), makeBook({ id: 2, tags: ['Owned'] })]

    const groups = groupSeriesBooksByAttribute(books, 'tags')
    expect(groups.map((g) => [g.key, g.label, g.books.map((b) => b.id)])).toEqual([
      ['owned', 'Owned', [2]],
      [SERIES_ATTRIBUTE_UNGROUPED_KEY, 'No tags', [1]],
    ])
  })
})
