<%#
  API representation of a Square payment source. Fifth and last of the partials
  Solidus derives from partial_name. Exposes only display fields -- never a
  token, never card data.
%>
json.source do
  if payment.source
    json.(payment.source, :id, :cc_type, :last_digits, :month, :year)
  else
    json.id nil
  end
end
