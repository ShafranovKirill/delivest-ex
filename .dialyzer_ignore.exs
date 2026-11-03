# Warnings that are false positives or defensive code, with a reason on every line.
[
  # Api.create/3 has no precise spec, so the defensive clause for an unexpected
  # 2xx body looks unreachable to Dialyzer while it is still needed at runtime.
  {"lib/delivest/integrations/yandex_delivery.ex", :pattern_match_cov}
]
