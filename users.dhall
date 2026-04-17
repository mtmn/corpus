let UserConfig =
      { listenbrainzUser : Optional Text
      , lastfmUser : Optional Text
      , databaseFile : Text
      , coverCacheEnabled : Bool
      , backupEnabled : Bool
      , backupIntervalHours : Natural
      , initialSync : Bool
      }

let defaults
    : UserConfig
    = { listenbrainzUser = None Text
      , lastfmUser = None Text
      , databaseFile = "corpus.db"
      , coverCacheEnabled = True
      , backupEnabled = False
      , backupIntervalHours = 1
      , initialSync = False
      }

in  { users =
      [ { slug = ""
        , config =
            defaults
            with listenbrainzUser = Some "mtmn"
            with databaseFile = "corpus-mtmn.db"
            with backupEnabled = True
        }
      ]
    }
