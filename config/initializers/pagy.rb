# Pagy initializer file (6.2.0)
# Instance variables
# See https://ddnexus.github.io/pagy/docs/api/pagy#instance-variables
Pagy::DEFAULT[:items] = 20        # items per page
Pagy::DEFAULT[:size]  = [1,4,4,1] # nav bar links

# Other defaults
# See https://ddnexus.github.io/pagy/docs/api/pagy#other-defaults
# Pagy::DEFAULT[:page_param] = :page # page param name
# Pagy::DEFAULT[:params] = {}        # params for URL
# Pagy::DEFAULT[:fragment] = '#fragment' # final fragment string

# Rails
# See https://ddnexus.github.io/pagy/docs/extras/rails
# require 'pagy/extras/rails'

# Array extra: Paginate arrays efficiently avoiding expensive array-wrapping and without overriding
# See https://ddnexus.github.io/pagy/docs/extras/array
# require 'pagy/extras/array'

# Countless extra: Paginate without any count, saving one query per rendering
# See https://ddnexus.github.io/pagy/docs/extras/countless
# require 'pagy/extras/countless'

# Elasticsearch Rails extra: Paginate `ElasticsearchRails` results
# See https://ddnexus.github.io/pagy/docs/extras/elasticsearch_rails
# require 'pagy/extras/elasticsearch_rails'

# Headers extra: Http response headers (and other helpers) useful for API pagination
# See http://ddnexus.github.io/pagy/extras/headers
# require 'pagy/extras/headers'

# Support extra: Extra support for features like: incremental, infinite, auto-scroll pagination
# See https://ddnexus.github.io/pagy/docs/extras/support
# require 'pagy/extras/support'

# Items extra: Allow the client to request a custom number of items per page with an optional selector UI
# See https://ddnexus.github.io/pagy/docs/extras/items
# require 'pagy/extras/items'
# set to false only if you want to make :enable_items_extra an opt-in variable
# Pagy::DEFAULT[:enable_items_extra] = false

# Overflow extra: Allow for easy handling of overflowing pages
# See https://ddnexus.github.io/pagy/docs/extras/overflow
# require 'pagy/extras/overflow'
# Pagy::DEFAULT[:overflow] = :empty_page    # default  (other options: :last_page and :exception)

# Metadata extra: Provides the pagination metadata to Javascript frameworks like Vue.js, react.js, etc.
# See https://ddnexus.github.io/pagy/docs/extras/metadata
# require 'pagy/extras/metadata'
# For performance reasons, you should explicitly set ONLY the metadata you use in the frontend
# Pagy::DEFAULT[:metadata] = [:scaffold_url, :count, :page, :prev, :next, :last]    # example

# Searchkick extra: Paginate `Searchkick` results
# See https://ddnexus.github.io/pagy/docs/extras/searchkick
# require 'pagy/extras/searchkick'

# Frontend Extras

# Bootstrap extra: Add nav, nav_js and combo_nav_js helpers and templates for Bootstrap pagination
# See https://ddnexus.github.io/pagy/docs/extras/bootstrap
require 'pagy/extras/bootstrap'

# Bulma extra: Add nav, nav_js and combo_nav_js helpers and templates for Bulma pagination
# See https://ddnexus.github.io/pagy/docs/extras/bulma
# require 'pagy/extras/bulma'

# Foundation extra: Add nav, nav_js and combo_nav_js helpers and templates for Foundation pagination
# See https://ddnexus.github.io/pagy/docs/extras/foundation
# require 'pagy/extras/foundation'

# Materialize extra: Add nav, nav_js and combo_nav_js helpers and templates for Materialize pagination
# See https://ddnexus.github.io/pagy/docs/extras/materialize
# require 'pagy/extras/materialize'

# Navs extra: Add nav_js and combo_nav_js helpers and templates for Navs pagination
# See https://ddnexus.github.io/pagy/docs/extras/navs
# require 'pagy/extras/navs'

# Semantic extra: Add nav, nav_js and combo_nav_js helpers and templates for Semantic UI pagination
# See https://ddnexus.github.io/pagy/docs/extras/semantic
# require 'pagy/extras/semantic'

# UIkit extra: Add nav, nav_js and combo_nav_js helpers and templates for UIkit pagination
# See https://ddnexus.github.io/pagy/docs/extras/uikit
# require 'pagy/extras/uikit'

# Multi size var used by the *_nav_js helpers
# See https://ddnexus.github.io/pagy/docs/extras/navs#steps
# Pagy::DEFAULT[:steps] = { 0 => [2,3,3,2], 540 => [3,5,5,3], 720 => [5,7,7,5] }

# I18n

# See https://ddnexus.github.io/pagy/docs/api/frontend#i18n
# Notice: No need to configure anything in this section if your app uses only "en" or "en-US" locale

# Locales: Load ~18 builtin locales (compared to the 310+ DateTime locales for Ruby)
# See https://ddnexus.github.io/pagy/docs/api/frontend#locales
# require 'pagy/extras/locales'

# I18n extra: uses the standard i18n gem which is ~18x slower using ~10x more memory
# See https://ddnexus.github.io/pagy/docs/extras/i18n
# require 'pagy/extras/i18n'

# Default i18n key
# Pagy::DEFAULT[:i18n_key] = 'pagy.item_name'   # default