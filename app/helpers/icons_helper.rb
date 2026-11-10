# Ícones do lucide (lucide.dev, licença ISC) embutidos como SVG inline:
# sem pacote JS, herdam a cor do texto (currentColor) e o tamanho do CSS.
# Os desenhos são constantes do código, nunca entrada de usuário.
module IconsHelper
  ICONS = {
    "layout-dashboard" => '<rect width="7" height="9" x="3" y="3" rx="1"/><rect width="7" height="5" x="14" y="3" rx="1"/>' \
                          '<rect width="7" height="9" x="14" y="12" rx="1"/><rect width="7" height="5" x="3" y="16" rx="1"/>',
    "plus" => '<path d="M5 12h14"/><path d="M12 5v14"/>',
    "briefcase" => '<path d="M16 20V4a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v16"/><rect width="20" height="14" x="2" y="6" rx="2"/>',
    "sun" => '<circle cx="12" cy="12" r="4"/><path d="M12 2v2"/><path d="M12 20v2"/><path d="m4.93 4.93 1.41 1.41"/>' \
             '<path d="m17.66 17.66 1.41 1.41"/><path d="M2 12h2"/><path d="M20 12h2"/><path d="m6.34 17.66-1.41 1.41"/>' \
             '<path d="m19.07 4.93-1.41 1.41"/>',
    "moon" => '<path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"/>',
    "monitor" => '<rect width="20" height="14" x="2" y="3" rx="2"/><path d="M8 21h8"/><path d="M12 17v4"/>',
    "menu" => '<path d="M4 6h16"/><path d="M4 12h16"/><path d="M4 18h16"/>',
    "x" => '<path d="M18 6 6 18"/><path d="m6 6 12 12"/>',
    "arrow-left" => '<path d="m12 19-7-7 7-7"/><path d="M19 12H5"/>',
    "clock" => '<circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/>',
    "cpu" => '<rect width="16" height="16" x="4" y="4" rx="2"/><rect width="6" height="6" x="9" y="9" rx="1"/>' \
             '<path d="M15 2v2"/><path d="M15 20v2"/><path d="M2 15h2"/><path d="M2 9h2"/><path d="M20 15h2"/>' \
             '<path d="M20 9h2"/><path d="M9 2v2"/><path d="M9 20v2"/>',
    "coins" => '<circle cx="8" cy="8" r="6"/><path d="M18.09 10.37A6 6 0 1 1 10.34 18"/><path d="M7 6h1v4"/>' \
               '<path d="m16.71 13.88.7.71-2.82 2.82"/>',
    "wrench" => '<path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z"/>',
    "shield-check" => '<path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z"/>' \
                      '<path d="m9 12 2 2 4-4"/>',
    "shield-alert" => '<path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z"/>' \
                      '<path d="M12 8v4"/><path d="M12 16h.01"/>',
    "users" => '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/>' \
               '<path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
    "bot" => '<path d="M12 8V4H8"/><rect width="16" height="12" x="4" y="8" rx="2"/><path d="M2 14h2"/>' \
             '<path d="M20 14h2"/><path d="M15 13v2"/><path d="M9 13v2"/>',
    "workflow" => '<rect width="8" height="8" x="3" y="3" rx="2"/><path d="M7 11v4a2 2 0 0 0 2 2h4"/>' \
                  '<rect width="8" height="8" x="13" y="13" rx="2"/>',
    "sparkles" => '<path d="M9.937 15.5A2 2 0 0 0 8.5 14.063l-6.135-1.582a.5.5 0 0 1 0-.962L8.5 9.936A2 2 0 0 0 9.937 8.5l1.582-6.135a.5.5 0 0 1 .963 0L14.063 8.5A2 2 0 0 0 15.5 9.937l6.135 1.581a.5.5 0 0 1 0 .964L15.5 14.063a2 2 0 0 0-1.437 1.437l-1.582 6.135a.5.5 0 0 1-.963 0z"/>' \
                  '<path d="M20 3v4"/><path d="M22 5h-4"/><path d="M4 17v2"/><path d="M5 18H3"/>',
    "inbox" => '<path d="M22 12h-6l-2 3h-4l-2-3H2"/>' \
               '<path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/>',
    "activity" => '<path d="M22 12h-4l-3 9L9 3l-3 9H2"/>',
    "circle-check" => '<circle cx="12" cy="12" r="10"/><path d="m9 12 2 2 4-4"/>',
    "circle-alert" => '<circle cx="12" cy="12" r="10"/><path d="M12 8v4"/><path d="M12 16h.01"/>',
    "ban" => '<circle cx="12" cy="12" r="10"/><path d="m4.9 4.9 14.2 14.2"/>',
    "globe" => '<circle cx="12" cy="12" r="10"/><path d="M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20"/><path d="M2 12h20"/>',
    "building" => '<rect width="16" height="20" x="4" y="2" rx="2"/><path d="M9 22v-4h6v4"/><path d="M8 6h.01"/>' \
                  '<path d="M16 6h.01"/><path d="M12 6h.01"/><path d="M12 10h.01"/><path d="M12 14h.01"/>' \
                  '<path d="M16 10h.01"/><path d="M16 14h.01"/><path d="M8 10h.01"/><path d="M8 14h.01"/>',
    "external-link" => '<path d="M15 3h6v6"/><path d="M10 14 21 3"/><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/>',
    "loader" => '<path d="M21 12a9 9 0 1 1-6.219-8.56"/>'
  }.freeze

  def icon(name, class_name: nil, label: nil)
    body = ICONS.fetch(name.to_s) # ícone inexistente é bug do código: falha alto.
    a11y = label ? { role: "img", "aria-label": label } : { "aria-hidden": "true" }

    tag.svg(
      body.html_safe, # rubocop:disable Rails/OutputSafety -- constante acima, sem entrada externa
      xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 24 24", fill: "none", stroke: "currentColor",
      "stroke-width": "2", "stroke-linecap": "round", "stroke-linejoin": "round",
      class: [ "icon", class_name ].compact.join(" "), **a11y
    )
  end
end
