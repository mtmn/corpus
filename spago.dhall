{ name = "scrobbler.purs"
, dependencies =
  [ "aff"
  , "console"
  , "effect"
  , "either"
  , "exceptions"
  , "node-buffer"
  , "node-event-emitter"
  , "node-http"
  , "node-net"
  , "node-streams"
  , "prelude"
  , "unsafe-coerce"
  ]
, packages = ./packages.dhall
, sources = [ "src/**/*.purs" ]
}
