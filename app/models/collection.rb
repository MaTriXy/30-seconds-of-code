class Collection < ApplicationRecord
  include CommonApi

  MAIN_COLLECTION_CID = 'snippets'.freeze
  COLLECTIONS_COLLECTION_CID = 'collections'.freeze
  MORE_COLLECTIONS_SUBLINK = {
    title: 'More',
    url: '/collections/p/1',
    icon: 'arrow-right',
    selected: false
  }.freeze

  # https://guides.rubyonrails.org/v5.0/association_basics.html
  has_one :parent,
    class_name: 'Collection',
    foreign_key: 'cid',
    primary_key: 'parent_cid',
    inverse_of: :children
  has_many :children,
    class_name: 'Collection',
    foreign_key: 'parent_cid',
    primary_key: 'cid',
    inverse_of: :parent

  has_many :collection_snippets,
    foreign_key: 'collection_cid'

  has_many :snippets,
    through: :collection_snippets

  scope :with_parent, -> { where.not(parent_cid: nil) }
  scope :snippet_collections, -> { where.not(cid: COLLECTIONS_COLLECTION_CID) }
  scope :primary, -> { where(top_level: true) }
  scope :secondary, -> { with_parent }
  scope :listed, -> { where(featured: true) }
  scope :featured, -> do
    where.not(featured_index: nil).order(featured_index: :asc)
  end

  # Cache the main collection on the class level to avoid repeated queries.
  @@main_collection = nil
  # Cache the collections collection on the class level to avoid repeated queries.
  @@collections_collection = nil

  def self.main
    @@main_collection ||= find(MAIN_COLLECTION_CID)
  end

  def self.collections
    @@collections_collection ||= find(COLLECTIONS_COLLECTION_CID)
  end

  def has_parent?
    parent_cid.present?
  end

  def is_main?
    cid == MAIN_COLLECTION_CID
  end

  def is_collections?
    cid == COLLECTIONS_COLLECTION_CID
  end

  def is_primary?
    top_level?
  end

  def is_secondary?
    has_parent?
  end

  def root_url
    # To avoid an extra query, we recreate the parent's slug here.
    has_parent? ? parent_cid.to_seo_slug : slug
  end

  def siblings
    has_parent? ? parent.children : []
  end

  def siblings_except_self
    siblings - [self]
  end

  def is_searchable
    featured?
  end

  def search_tokens_array
    _tokens.split(';')
  end

  def first_page_slug
    "#{slug}/p/1"
  end

  def page_count
    (listed_snippet_count / Orbit::settings[:cards_per_page]).ceil
  end

  def listed_snippets
    collection_snippets.
      published.
      listed.
      by_position.
      joins(:snippet).
      # merge(Snippet.published).
      # where.not(collection_snippets: { position: -1 }).
      # order('collection_snippets.position asc').
      preload(:snippet).
      map(&:snippet)
  end

  def listed_snippet_count
    @listed_snippet_count ||= collection_snippets.published.listed.count
  end

  def formatted_snippet_count
    "#{listed_snippet_count} snippets"
  end

  def formatted_description
    description.strip_html_paragraphs_and_links
  end

  # TODO: Extract into a presenter ideally
  def sublinks
    sublink_presenter.sublinks
  end

  # TODO: A little fiddly
  def matches_tag(tag)
    cid.end_with?("/#{tag}")
  end

  def pages
    return @pages = collections_pages if cid == COLLECTIONS_COLLECTION_CID

    @pages ||= (1..page_count).map do |page_number|
      Page.from(
        self,
        page_number: page_number,
        page_count: page_count,
        items: listed_snippets.slice(
          (page_number - 1) * Orbit::settings[:cards_per_page],
          Orbit::settings[:cards_per_page]
        ),
        item_count: listed_snippet_count,
        item_type: 'snippets',
        large_images: false
      )
    end
  end

  private

  def collections_pages
    return @collections_pages if defined?(@collections_pages)

    featured_collections = Collection.featured
    featured_collections_count = featured_collections.count
    page_count = (featured_collections_count / Orbit::settings[:collection_cards_per_page]).ceil

    @collections_pages ||= (1..page_count).map do |page_number|
      Page.from(
        self,
        page_number: page_number,
        page_count: page_count,
        collections_count: featured_collections_count,
        items: featured_collections.slice(
          (page_number - 1) * Orbit::settings[:collection_cards_per_page],
          Orbit::settings[:collection_cards_per_page]
        ),
        item_count: featured_collections_count,
        item_type: 'collections',
        large_images: true
      )
    end
  end

  def sublink_presenter
    @sublink_presenter ||= SublinkPresenter.new(self)
  end
end
