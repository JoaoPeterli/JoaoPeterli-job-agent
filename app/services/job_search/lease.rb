module JobSearch
  # Representa uma aquisição de lease de execução.
  #
  # - token: identifica esta aquisição específica (compare-and-set no banco)
  # - fencing_token: número monotônico por chave; cresce a cada nova
  #   aquisição e nunca é reiniciado. Deve ser enviado a recursos externos
  #   para que eles rejeitem escritas de workers obsoletos.
  Lease = Data.define(:key, :token, :fencing_token)
end
