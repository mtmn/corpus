module Types exposing (ActiveFilter, ApproveResponse, Flags, Listen, Model, Msg(..), Page(..), Period(..), RegField(..), Registration, SimilarState(..), SimilarTrack, Stats, StatsEntry, Tab(..), UserInfo)

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
    , registrationEnabled : Bool
    , adminToken : String
    }



-- TYPES


type Tab
    = ListensTab
    | StatsTab
    | AboutTab


{-| Which top-level page the SPA shows, derived from the URL path.
-}
type Page
    = MainPage
    | RegisterPage
    | AdminPage


{-| A pending registration request, as listed on the admin page.
-}
type alias Registration =
    { id : String
    , slug : String
    , name : String
    , email : String
    , listenbrainzUser : Maybe String
    , lastfmUser : Maybe String
    }


type alias ApproveResponse =
    { status : String
    , token : Maybe String
    }


{-| Fields of the registration form, used by the UpdateRegField message.
-}
type RegField
    = FSlug
    | FName
    | FEmail
    | FLbUser
    | FLfUser


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
    , page : Page
    , registrationEnabled : Bool

    -- Registration form
    , regSlug : String
    , regName : String
    , regEmail : String
    , regLbUser : String
    , regLfUser : String
    , regSubmitting : Bool
    , regSubmitted : Bool
    , regError : Maybe String

    -- Admin page
    , adminToken : String
    , adminTokenInput : String
    , registrations : List Registration
    , users : List Registration
    , confirmingRemoval : Maybe String
    , adminError : Maybe String
    , approvedToken : Maybe String
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
    | CoverBackgroundClick
    | ExpandSection String
    | ShowAllSection String
    | CollapseSection String
    | FetchSimilar Int String String
    | FetchSimilarTracks Int String String (Result Http.Error (List SimilarTrack))
    | UpdateSearchInput String
    | SubmitSearch
    | ClearSearch
    | UpdateRegField RegField String
    | SubmitRegistration
    | GotRegistrationResult (Result String ())
    | UpdateAdminTokenInput String
    | SaveAdminToken
    | FetchRegistrations
    | GotRegistrations (Result Http.Error (List Registration))
    | ApproveRegistration String
    | DenyRegistration String
    | GotApproveResult (Result Http.Error ApproveResponse)
    | GotDenyResult (Result String ())
    | FetchUsers
    | GotUsers (Result Http.Error (List Registration))
    | RequestRemoveUser String
    | CancelRemoveUser
    | RemoveUser String
    | GotRemoveResult (Result String ())
    | UrlRequested Browser.UrlRequest
    | UrlChanged Url.Url



-- UPDATE
