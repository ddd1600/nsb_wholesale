module LayoutHelper
  # Generates a simple canonical tag based on the request path, preserving allowed
  # parameters. For collection actions, a trailing slash is added to the href.
  # For more advanced use cases, consider using the `canonical-rails` gem.
  #
  # @see https://github.com/jumph4x/canonical-rails
  # @see https://developers.google.com/search/docs/crawling-indexing/consolidate-duplicate-urls
  #
  # @param host [String] the host to use in the canonical URL
  # @param collection_actions [Array<String>] the actions that will include a trailing slash
  # @param allowed_parameters [Array<Symbol>] the parameters to preserve in the canonical URL
  # @return [String] the generated link rel="canonical" tag
  def simple_canonical_tag(
    host: current_store&.url,
    collection_actions: %w[index],
    allowed_parameters: [:keywords, :page, :search, :taxon]
  )
    # params[:format] is attacker-controlled (?format=...), and the starter
    # frontend interpolated it straight into a Regexp -- a ReDoS vector flagged
    # by Brakeman, on every page that renders a canonical tag. String suffix
    # removal does the same job with no pattern compilation at all.
    format = params[:format].to_s
    path_without_extension = request.path
    path_without_extension = path_without_extension.delete_suffix(".#{format}") if format.present?
    path_without_extension = path_without_extension.delete_suffix("/")

    href = "#{request.protocol}#{host}#{path_without_extension}"

    trailing_slash = request.params.key?('action') &&
      collection_actions.include?(request.params['action'])
    href += '/' if trailing_slash

    query_params = params.select do |key, value|
      value.present? && allowed_parameters.include?(key.to_sym)
    end.to_unsafe_h

    href += "?#{query_params.to_query}" if query_params.present?

    tag(:link, rel: :canonical, href: href)
  end
end
