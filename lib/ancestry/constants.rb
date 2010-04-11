module Ancestry

  DEPTH_SCOPES = {
    :before_depth => '<',
    :to_depth     => '<=',
    :at_depth     => '=',
    :from_depth   => '>=',
    :after_depth  => '>'
  }

  ORPHAN_STRATEGIES = [ :rootify, :restrict, :destroy ]

  DEFAULT_ORPHAN_STRATEGY = :destroy

end
