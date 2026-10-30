defmodule Delivest.Fiscal.Vat do
  @rates [:none, :vat0, :vat5, :vat7, :vat10, :vat20, :vat22]

  def rates, do: @rates
end
