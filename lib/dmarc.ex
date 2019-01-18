defmodule DMARC do
  require Logger

  def organization(host) when is_binary(host),
    do: organization(host |> String.downcase() |> String.split(".") |> Enum.reverse())

  :ssl.start()
  :inets.start()
  url = "https://publicsuffix.org/list/effective_tld_names.dat"

  case :httpc.request(:get, {'#{url}', []}, [], body_format: :binary) do
    {:ok, {{_, 200, _}, _, r}} ->
      r

    e ->
      Logger.error("Download failed! fallback on \"priv/suffix.data\"\nERROR: #{inspect(e)}")
      File.read!("#{:code.priv_dir(:mailibex)}/suffix.data")
  end
  |> String.trim()
  |> String.split("\n")
  # remove comments
  |> Enum.filter(fn
    <<c, _::binary>> -> not (c in [?\s, ?/])
    _ -> false
  end)
  # divide domain components
  |> Enum.map(&String.split(&1, "."))
  # sort rule by priority 
  |> Enum.sort(fn
    # exception rules are first ones
    ["!" <> _ | _], _ ->
      true

    # 
    _, ["!" <> _ | _] ->
      false

    # else priority to longest prefix match 
    x, y ->
      length(x) > length(y)
  end)
  |> Enum.each(fn spec ->
    # ["com","*","pref"] -> must match ["com",_,"pref",_org|_rest]
    org_match =
      (spec
       |> Enum.reverse()
       |> Enum.map(fn
         # remove exception mark ! 
         "!" <> rest ->
           rest

         # "*" component matches anything, so convert it to "_"
         "*" ->
           quote do: _

         # match other components as they are
         x ->
           x
       end)) ++ quote do: [_org | _rest]

    # and 3+1=4 first components is organization
    org_len = length(spec) + 1

    def organization(unquote(org_match) = host),
      do: host |> Enum.take(unquote(org_len)) |> Enum.reverse() |> Enum.join(".")
  end)

  def organization([unknown_tld, org | _]), do: "#{org}.#{unknown_tld}"

  def organization(host), do: host |> Enum.reverse() |> Enum.join(".")
end
