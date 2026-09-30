/// A hand-written corpus that exercises every part of the brain: lists, reminders with dates,
/// links, ideas, and Italian notes across all ontology domains.
///
/// It is used by the tests (`test/brain_quality_test.dart`) and by the app's "Try with sample
/// notes" action, so what you see in the demo is exactly what the tests verify.
class SampleNote {
  const SampleNote(this.text, {this.expectCategory, this.minutesAgo = 0});

  final String text;

  /// Domain the brain should choose (null = no expectation). Alternatives are separated by `|`
  /// for notes that genuinely sit between domains (`'shopping|food'`).
  final String? expectCategory;

  bool accepts(String? categoryId) => expectCategory == null || expectCategory!.split('|').contains(categoryId);

  /// How long ago the note was "written" (spreads timestamps in the demo).
  final int minutesAgo;
}

const List<SampleNote> sampleCorpus = [
  // Groceries & shopping
  SampleNote('milk and eggs', expectCategory: 'shopping', minutesAgo: 5),
  SampleNote('Buy bread, pasta and tomatoes', expectCategory: 'shopping|food', minutesAgo: 90),
  SampleNote(
    'Shopping list:\n- [ ] olive oil\n- [ ] basil\n- [ ] parmesan\n- [x] coffee',
    expectCategory: 'shopping',
    minutesAgo: 240,
  ),
  SampleNote('Birthday gift ideas for Anna: a book, a scarf, headphones', minutesAgo: 600),
  SampleNote('Order laundry detergent and toilet paper', expectCategory: 'shopping', minutesAgo: 1000),

  // Tasks with dates
  SampleNote('Remind me to call mom tomorrow at 5pm', minutesAgo: 20),
  SampleNote('Dentist appointment Tuesday 4pm', expectCategory: 'health', minutesAgo: 300),
  SampleNote('Pay the electricity bill before Friday', expectCategory: 'finance', minutesAgo: 400),
  SampleNote('Renew passport by 15 October', minutesAgo: 700),
  SampleNote('Call mom about Sunday lunch', expectCategory: 'people', minutesAgo: 820),

  // Travel cluster
  SampleNote('Book flights to Lisbon for October', expectCategory: 'travel', minutesAgo: 1500),
  SampleNote('Hotel near Alfama in Lisbon, check-in 12 October', expectCategory: 'travel', minutesAgo: 1600),
  SampleNote(
    'Lisbon itinerary: Belém tower, pastel de nata, tram 28, sunset at the viewpoint',
    expectCategory: 'travel',
    minutesAgo: 1700,
  ),
  SampleNote('Need to renew passport before the Lisbon trip', minutesAgo: 1800),

  // Work
  SampleNote('Quarterly budget review with finance team', minutesAgo: 2000),
  SampleNote('Meeting notes: roadmap planning with the design team', expectCategory: 'work', minutesAgo: 2100),
  SampleNote('Follow up with Sarah about the Q4 client proposal by Thursday', expectCategory: 'work', minutesAgo: 2200),
  SampleNote('Prepare slides for Monday client presentation', expectCategory: 'work', minutesAgo: 2300),

  // Tech & AI
  SampleNote('Fix the login bug in the mobile app', expectCategory: 'tech', minutesAgo: 3000),
  SampleNote('Research vector databases for the notes app', expectCategory: 'tech', minutesAgo: 3100),
  SampleNote('Learn about neural networks and transformers', expectCategory: 'tech', minutesAgo: 3200),
  SampleNote('https://arxiv.org/abs/1706.03762 attention is all you need', minutesAgo: 3300),

  // Ideas
  SampleNote('Idea: an app that reminds me to water the plants', expectCategory: 'ideas', minutesAgo: 4000),
  SampleNote('Startup idea: marketplace for local repair shops', expectCategory: 'ideas', minutesAgo: 4100),
  SampleNote('Blog post idea: why local-first software matters', expectCategory: 'ideas', minutesAgo: 4200),

  // Health & fitness
  SampleNote('Go for a 5k run tomorrow morning', expectCategory: 'health', minutesAgo: 5000),
  SampleNote('Book annual blood test and eye exam', expectCategory: 'health', minutesAgo: 5100),
  SampleNote('Try meditation before bed, my sleep has been bad', expectCategory: 'health', minutesAgo: 5200),

  // Home
  SampleNote('Clean the apartment this weekend', expectCategory: 'home', minutesAgo: 6000),
  SampleNote('Fix the leaking kitchen tap, call the plumber', expectCategory: 'home', minutesAgo: 6100),
  SampleNote('Water the basil and the succulents on the balcony', expectCategory: 'home', minutesAgo: 6200),

  // Learning, finance, media, personal
  SampleNote("Read 'Thinking, Fast and Slow' chapter 3", expectCategory: 'learning', minutesAgo: 7000),
  SampleNote('Compare ETFs for long-term retirement savings', expectCategory: 'finance', minutesAgo: 7100),
  SampleNote('Watch list: Dune Part Two, Oppenheimer, The Bear', expectCategory: 'media', minutesAgo: 7200),
  SampleNote('Goal: read 24 books this year and run a half marathon', minutesAgo: 7300),
  SampleNote('"We are what we repeatedly do" - Aristotle', minutesAgo: 7400),

  // Italian
  SampleNote('Comprare latte, uova e pane', expectCategory: 'shopping', minutesAgo: 8000),
  SampleNote('Ricordami di pagare l\'affitto entro venerdì', expectCategory: 'finance', minutesAgo: 8100),
  SampleNote('Appuntamento dal dentista venerdì alle 17', expectCategory: 'health', minutesAgo: 8200),
  SampleNote('Prenotare un hotel a Roma per novembre', expectCategory: 'travel', minutesAgo: 8300),
  SampleNote('Idea per una app di ricette con gli ingredienti del frigo', expectCategory: 'ideas', minutesAgo: 8400),
];
