module Types exposing (ActiveFilter, Flags, Listen, Model, Msg(..), Period(..), SimilarState(..), SimilarTrack, Stats, StatsEntry, Tab(..), UserInfo)

import Browser
import Browser.Navigation as Nav
import Dict exposing (Dict)
import Http
import Set exposing (Set)
import Time
import Url


type alias UserInfo =
    { slug : String
    , name : String
    }


type alias Flags =
    { userSlug : String
    , allUsers : List UserInfo
    }



-- TYPES


type Tab
    = ListensTab
    | StatsTab
    | AboutTab


type Period
    = AllTime
    | LastDays Int
    | CustomRange String String


type alias ActiveFilter =
    { field : String
    , value : String
    }


type alias Listen =
    { trackName : Maybe String
    , artistName : Maybe String
    , releaseName : Maybe String
    , listenedAt : Maybe Int
    , genre : Maybe String
    , label : Maybe String
    , releaseMbid : Maybe String
    , caaReleaseMbid : Maybe String
    }


type alias StatsEntry =
    { name : String
    , count : Int
    }


type alias Stats =
    { genres : List StatsEntry
    , labels : List StatsEntry
    , years : List StatsEntry
    , artists : List StatsEntry
    , tracks : List StatsEntry
    }


type alias SimilarTrack =
    { artist : String
    , track : String
    , score : Maybe Float
    , videoUri : Maybe String
    }


type SimilarState
    = SimilarLoading
    | SimilarLoaded (List SimilarTrack)
    | SimilarError String



-- MODEL


type alias Model =
    { navKey : Nav.Key
    , listens : List Listen
    , stats : Maybe Stats
    , error : Maybe String
    , loading : Bool
    , currentTime : Maybe Time.Posix
    , failedCovers : Set String
    , hoveredCover : Maybe Int
    , expandedSections : Set String
    , loadedSections : Set String
    , offset : Int
    , limit : Int
    , activeTab : Tab
    , activeFilter : Maybe ActiveFilter
    , statsPeriod : Period
    , customInput : String
    , showCustomInput : Bool
    , customError : Maybe String
    , userSlug : String
    , similarStates : Dict String SimilarState
    , allUsers : List UserInfo
    , searchInput : String
    , activeSearch : Maybe String
    }


type Msg
    = GotListens (Result Http.Error (List Listen))
    | GotStats (Result Http.Error Stats)
    | GotSectionData String (Result Http.Error (List StatsEntry))
    | Tick Time.Posix
    | GotTime Time.Posix
    | ImageError String
    | NextPage
    | PrevPage
    | SwitchTab Tab
    | SetStatsPeriod Period
    | OpenCustomInput
    | UpdateCustomInput String
    | ApplyCustomPeriod
    | FilterBy String String
    | ClearFilter
    | HoverCover Int
    | UnhoverCover
    | ExpandSection String
    | ShowAllSection String
    | CollapseSection String
    | FetchSimilar String String
    | FetchSimilarTracks String String (Result Http.Error (List SimilarTrack))
    | UpdateSearchInput String
    | SubmitSearch
    | ClearSearch
    | UrlRequested Browser.UrlRequest
    | UrlChanged Url.Url



-- UPDATE
