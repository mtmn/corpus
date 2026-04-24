-- DEPRECATED: users.dhall is no longer the source of truth.
-- Manage users directly in users.json using the CLI:
--   node server.js add-user --slug <slug> --db <file> [--name <name>]
--   node server.js list-users
--   node server.js reset-token --slug <slug>

let UserConfig =
      { name : Optional Text
      , listenbrainzUser : Optional Text
      , lastfmUser : Optional Text
      , databaseFile : Text
      , coverCacheEnabled : Bool
      , backupEnabled : Bool
      , backupIntervalHours : Natural
      }

let defaults
    : UserConfig
    = { name = None Text
      , listenbrainzUser = None Text
      , lastfmUser = None Text
      , databaseFile = "corpus.db"
      , coverCacheEnabled = True
      , backupEnabled = False
      , backupIntervalHours = 24
      }

in  { users =
      [ { slug = ""
        , name = Some "mtmn"
        , config =
            defaults
            with listenbrainzUser = Some "mtmn"
            with databaseFile = "corpus-mtmn.db"
            with backupEnabled = True
        }
      , { slug = "mtmnn"
        , name = Some "mtmn (last.fm)"
        , config =
            defaults
            with lastfmUser = Some "mtmnn"
            with databaseFile = "corpus-lastfm-mtmnn.db"
            with backupEnabled = True
        }
      ]
    }
