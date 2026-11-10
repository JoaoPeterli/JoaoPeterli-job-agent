module JobSearch
  # Este worker perdeu o lease do run (ex.: ficou pausado tempo demais e
  # outro worker assumiu). Ele precisa parar sem gravar nada.
  class RunLeaseLost < RunInterrupted; end
end
