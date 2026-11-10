module JobSearch
  # Texto de uma vaga para o embedding: o que define a vaga (cargo, stack,
  # local, modalidade), sem link nem data. Mesma função para vagas e para
  # as marcações 👍/👎, para que os vetores sejam comparáveis.
  module JobText
    module_function

    def for(job)
      job = job.to_h.transform_keys(&:to_sym)

      [
        job[:title],
        ("at #{job[:company]}" if job[:company].present?),
        job[:location],
        job[:remote] ? "remote" : "on-site",
        Array(job[:tags]).first(10).join(", ").presence
      ].compact_blank.join(" | ")
    end
  end
end
