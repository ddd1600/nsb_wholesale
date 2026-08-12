//= link_tree ../images
//= link_directory ../stylesheets .css
//= link_tree ../builds

// Tailwind's compiled bundle, referenced by layouts/storefront.html.erb via
// stylesheet_link_tag "tailwind". Declared explicitly as well as via
// link_tree ../builds so it resolves regardless of build order.
//= link tailwind.css
