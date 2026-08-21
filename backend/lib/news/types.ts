export type NewsSearchInput = {
  topicID: string;
  query: string;
  language?: "japanese" | "english";
  sourceCountry?: string;
  limit?: number;
};

export type NewsCandidate = {
  topicID?: string;
  url: string;
  title: string;
  description?: string;
  imageURL?: string;
  sourceDomain: string;
  language: string;
  country?: string;
  publishedAt: string;
  providerID?: string;
};

export type NewsProvider = {
  readonly name: string;
  search(input: NewsSearchInput): Promise<NewsCandidate[]>;
};
