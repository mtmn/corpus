module State exposing (Query, buildQuery, init, landingTab, parsePage, parsePageParam, parseQuery, parseTabParam, similarKey, subscriptions, update, userPath)

import Api exposing (approveRegistration, denyRegistration, fetchListens, fetchRegistrations, fetchSectionData, fetchSimilarTracks, fetchStats, fetchUsers, httpErrorToString, removeUser, submitRegistration)
import Browser
import Browser.Events
import Browser.Navigation as Nav
import Dict
import Json.Decode as D
import Ports
import Set
import Task
import Time
import Types exposing (Flags, Model, Msg(..), Page(..), Period(..), RegField(..), SimilarState(..), Stats, StatsEntry, Tab(..))
import Url


init : Flags -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init flags url navKey =
    let
        q =
            parseQuery url

        offset =
            max 0 ((q.page - 1) * 25)

        page =
            parsePage url

        initialFilter =
            case q.filterField of
                Just field ->
                    Maybe.map (\value -> { field = field, value = value }) q.filterValue

                Nothing ->
                    Nothing
    in
    ( { navKey = navKey
      , listens = []
      , stats = Nothing
      , error = Nothing
      , hasMoreListens = False
      , loading = True
      , currentTime = Nothing
      , failedCovers = Set.empty
      , hoveredCover = Nothing
      , expandedSections = Set.empty
      , loadedSections = Set.empty
      , offset = offset
      , limit = 25
      , activeTab = q.tab
      , activeFilter = initialFilter
      , statsPeriod = AllTime
      , customInput = ""
      , showCustomInput = False
      , customError = Nothing
      , userSlug = flags.userSlug
      , similarStates = Dict.empty
      , allUsers = flags.allUsers
      , searchInput = Maybe.withDefault "" q.search
      , activeSearch = q.search
      , page = page
      , visibility = Browser.Events.Visible
      , registrationEnabled = flags.registrationEnabled
      , regSlug = ""
      , regName = ""
      , regEmail = ""
      , regLbUser = ""
      , regLfUser = ""
      , regSubmitting = False
      , regSubmitted = False
      , regError = Nothing
      , adminToken = flags.adminToken
      , adminTokenInput = flags.adminToken
      , registrations = []
      , users = []
      , confirmingRemoval = Nothing
      , adminError = Nothing
      , approvedToken = Nothing
      }
    , case page of
        AdminPage ->
            Cmd.batch
                [ Task.perform GotTime Time.now
                , if String.isEmpty flags.adminToken then
                    Cmd.none

                  else
                    Cmd.batch [ fetchRegistrations flags.adminToken, fetchUsers flags.adminToken ]
                ]

        RegisterPage ->
            Task.perform GotTime Time.now

        MainPage ->
            Cmd.batch
                ([ fetchListens flags.userSlug 25 offset initialFilter q.search
                 , Task.perform GotTime Time.now
                 ]
                    ++ (if q.tab == StatsTab then
                            [ fetchStats flags.userSlug AllTime ]

                        else
                            []
                       )
                )
    )


parsePage : Url.Url -> Page
parsePage url =
    case url.path of
        "/register" ->
            RegisterPage

        "/admin" ->
            AdminPage

        _ ->
            MainPage


{-| Pick the tab to show after a URL change lands on the main page.
Arriving from another page keeps the tab the user chose; navigating within
the main page resets to listens.
-}
landingTab : Page -> Tab -> Tab
landingTab fromPage currentTab =
    if fromPage == MainPage then
        ListensTab

    else
        currentTab


userPath : String -> String
userPath slug =
    if String.isEmpty slug then
        "/"

    else
        "/u/" ++ slug


fetchTabData : Model -> Cmd Msg
fetchTabData model =
    case model.activeTab of
        StatsTab ->
            if model.stats == Nothing then
                fetchStats model.userSlug model.statsPeriod

            else
                Cmd.none

        ListensTab ->
            Cmd.none

        AboutTab ->
            Cmd.none


parsePageParam : Url.Url -> Int
parsePageParam url =
    queryParam url "page"
        |> Maybe.andThen String.toInt
        |> Maybe.withDefault 1
        |> max 1


{-| The list view state carried in the URL, so reload, back and link sharing
restore the same view.
-}
type alias Query =
    { page : Int
    , filterField : Maybe String
    , filterValue : Maybe String
    , search : Maybe String
    , tab : Tab
    }


-- | Parse the page, filter, search and tab out of a URL.
parseQuery : Url.Url -> Query
parseQuery url =
    let
        mField =
            queryParam url "filterField"

        mValue =
            queryParam url "filterValue"
    in
    { page = parsePageParam url
    , filterField = mField
    , filterValue = mValue
    , search = queryParam url "search"
    , tab = parseTabParam url
    }


-- | Parse the tab, defaulting to the listens tab.
parseTabParam : Url.Url -> Tab
parseTabParam url =
    case queryParam url "tab" of
        Just "stats" ->
            StatsTab

        Just "about" ->
            AboutTab

        _ ->
            ListensTab


-- | Read one decoded query parameter. Works for any path shape, unlike a
-- | `Url.Parser` query parser, which only runs on the route it is attached to.
queryParam : Url.Url -> String -> Maybe String
queryParam url name =
    parseQueryParams (Maybe.withDefault "" url.query)
        |> List.filterMap
            (\( key, value ) ->
                if key == name && not (String.isEmpty value) then
                    Just value

                else
                    Nothing
            )
        |> List.head


-- | Split a raw query string into percent-decoded key/value pairs.
parseQueryParams : String -> List ( String, String )
parseQueryParams raw =
    raw
        |> String.split "&"
        |> List.filter (not << String.isEmpty)
        |> List.map
            (\pair ->
                let
                    parts =
                        String.split "=" pair

                    decode =
                        Url.percentDecode >> Maybe.withDefault ""
                in
                ( parts |> List.head |> Maybe.withDefault "" |> decode
                , parts |> List.drop 1 |> String.join "=" |> decode
                )
            )


-- | The query implied by the model's current view state.
currentQuery : Model -> Int -> Query
currentQuery model page =
    { page = page
    , filterField = Maybe.map .field model.activeFilter
    , filterValue = Maybe.map .value model.activeFilter
    , search = model.activeSearch
    , tab = model.activeTab
    }


-- | Whether the URL names a tab explicitly. A missing tab means "keep what
-- | the user chose" (see landingTab), which is not the same as "listens".
hasTabParam : Url.Url -> Bool
hasTabParam url =
    queryParam url "tab" /= Nothing


-- | Build a URL path plus query for the given view state.
buildQuery : String -> Query -> String
buildQuery slug q =
    let
        params =
            List.filterMap identity
                [ Just ("page", String.fromInt q.page)
                , Maybe.map (\f -> ( "filterField", f )) q.filterField
                , Maybe.map (\v -> ( "filterValue", v )) q.filterValue
                , Maybe.map (\s -> ( "search", s )) q.search
                , Just
                    ( "tab"
                    , case q.tab of
                        ListensTab ->
                            "listens"

                        StatsTab ->
                            "stats"

                        AboutTab ->
                            "about"
                    )
                ]

        encoded =
            String.join "&"
                (List.map (\( k, v ) -> k ++ "=" ++ Url.percentEncode v) params)
    in
    userPath slug ++ "?" ++ encoded



-- MSG


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UrlRequested urlRequest ->
            case urlRequest of
                Browser.Internal url ->
                    if String.isEmpty url.path then
                        ( model, Cmd.none )

                    else
                        ( model, Nav.pushUrl model.navKey (Url.toString url) )

                Browser.External href ->
                    ( model, Nav.load href )

        UrlChanged url ->
            case parsePage url of
                RegisterPage ->
                    ( { model | page = RegisterPage }, Cmd.none )

                AdminPage ->
                    ( { model | page = AdminPage, approvedToken = Nothing, confirmingRemoval = Nothing }
                    , if String.isEmpty model.adminToken then
                        Cmd.none

                      else
                        Cmd.batch [ fetchRegistrations model.adminToken, fetchUsers model.adminToken ]
                    )

                MainPage ->
                    let
                        newUserSlug =
                            if String.startsWith "/u/" url.path then
                                String.dropLeft 3 url.path

                            else
                                ""

                        q =
                            parseQuery url

                        targetOffset =
                            max 0 ((q.page - 1) * model.limit)

                        -- The URL is the source of truth: a bare path means no
                        -- filter and no search.
                        targetFilter =
                            case q.filterField of
                                Just field ->
                                    Maybe.map (\value -> { field = field, value = value }) q.filterValue

                                Nothing ->
                                    Nothing

                        targetSearch =
                            q.search

                        targetTab =
                            if hasTabParam url then
                                q.tab

                            else
                                landingTab model.page model.activeTab

                        userChanged =
                            newUserSlug /= model.userSlug

                        shouldLoad =
                            model.page /= MainPage || userChanged || model.offset /= targetOffset || model.activeFilter /= targetFilter || model.activeSearch /= targetSearch || model.activeTab /= targetTab
                    in
                    if shouldLoad then
                        let
                            newModel =
                                { model
                                    | userSlug = newUserSlug
                                    , offset = targetOffset
                                    , activeFilter = targetFilter
                                    , activeSearch = targetSearch
                                    , searchInput = Maybe.withDefault "" targetSearch
                                    , activeTab = targetTab
                                    , loading = True
                                    , page = MainPage
                                }

                            clearedModel =
                                if userChanged then
                                    { newModel
                                        | stats = Nothing
                                        , expandedSections = Set.empty
                                        , loadedSections = Set.empty
                                        , similarStates = Dict.empty
                                    }

                                else
                                    newModel
                        in
                        ( clearedModel
                        , Cmd.batch
                            [ fetchListens newUserSlug model.limit targetOffset targetFilter targetSearch
                            , fetchTabData clearedModel
                            ]
                        )

                    else
                        ( { model | page = MainPage }, Cmd.none )

        Tick time ->
            if model.page == MainPage && model.activeTab == ListensTab && model.visibility == Browser.Events.Visible && not model.loading then
                ( { model | currentTime = Just time, loading = True }
                , fetchListens model.userSlug model.limit model.offset model.activeFilter model.activeSearch
                )

            else
                ( { model | currentTime = Just time }, Cmd.none )

        VisibilityChanged vis ->
            ( { model | visibility = vis }, Cmd.none )

        GotTime time ->
            ( { model | currentTime = Just time }, Cmd.none )

        GotListens result ->
            let
                newModel =
                    case result of
                        Err err ->
                            { model | loading = False, error = Just (httpErrorToString err) }

                        Ok page ->
                            { model | loading = False, listens = page.listens, hasMoreListens = page.hasMore, error = Nothing }
            in
            ( newModel, Task.perform GotTime Time.now )

        GotStats result ->
            case result of
                Err err ->
                    ( { model | error = Just (httpErrorToString err) }, Cmd.none )

                Ok stats ->
                    ( { model | stats = Just stats, error = Nothing }, Cmd.none )

        GotSectionData section result ->
            case result of
                Err err ->
                    ( { model | error = Just (httpErrorToString err) }, Cmd.none )

                Ok entries ->
                    ( { model
                        | expandedSections = Set.insert section model.expandedSections
                        , loadedSections = Set.insert section model.loadedSections
                        , stats = Maybe.map (patchStatSection section entries) model.stats
                        , error = Nothing
                      }
                    , Cmd.none
                    )

        ImageError url ->
            ( { model | failedCovers = Set.insert url model.failedCovers }, Cmd.none )

        NextPage ->
            let
                newOffset =
                    model.offset + model.limit

                page =
                    newOffset // model.limit + 1
            in
            ( { model | offset = newOffset, loading = True }
            , Cmd.batch
                [ fetchListens model.userSlug model.limit newOffset model.activeFilter model.activeSearch
                , Nav.pushUrl model.navKey (buildQuery model.userSlug (currentQuery model page))
                ]
            )

        PrevPage ->
            let
                newOffset =
                    max 0 (model.offset - model.limit)

                page =
                    newOffset // model.limit + 1
            in
            ( { model | offset = newOffset, loading = True }
            , Cmd.batch
                [ fetchListens model.userSlug model.limit newOffset model.activeFilter model.activeSearch
                , Nav.pushUrl model.navKey (buildQuery model.userSlug (currentQuery model page))
                ]
            )

        SwitchTab tab ->
            let
                newModel =
                    { model | activeTab = tab }
            in
            if model.page == MainPage then
                ( newModel
                , Cmd.batch
                    [ fetchTabData newModel
                    , Nav.pushUrl model.navKey
                        (buildQuery model.userSlug
                            { filterField = Maybe.map .field model.activeFilter
                            , filterValue = Maybe.map .value model.activeFilter
                            , search = model.activeSearch
                            , tab = tab
                            , page = model.offset // model.limit + 1
                            }
                        )
                    ]
                )

            else
                -- Leaving /register or /admin: return to the current user's
                -- page. UrlChanged keeps the chosen tab and loads the listens.
                ( newModel, Nav.pushUrl model.navKey (userPath model.userSlug) )

        SetStatsPeriod period ->
            ( { model
                | statsPeriod = period
                , stats = Nothing
                , expandedSections = Set.empty
                , loadedSections = Set.empty
                , showCustomInput = False
              }
            , fetchStats model.userSlug period
            )

        OpenCustomInput ->
            let
                prefill =
                    case model.statsPeriod of
                        CustomRange from to ->
                            from ++ " " ++ to

                        _ ->
                            model.customInput
            in
            ( { model | showCustomInput = True, customInput = prefill, customError = Nothing }
            , Cmd.none
            )

        UpdateCustomInput str ->
            ( { model | customInput = str, customError = Nothing }, Cmd.none )

        ApplyCustomPeriod ->
            let
                parts =
                    model.customInput
                        |> String.split " "
                        |> List.filter (not << String.isEmpty)
            in
            case parts of
                [ from, to ] ->
                    if String.length from /= 10 || String.length to /= 10 then
                        ( { model | customError = Just "Dates must be in YYYY-MM-DD format" }, Cmd.none )

                    else if from > to then
                        ( { model | customError = Just "'from' must be before 'to'" }, Cmd.none )

                    else
                        let
                            period =
                                CustomRange from to
                        in
                        ( { model
                            | statsPeriod = period
                            , stats = Nothing
                            , expandedSections = Set.empty
                            , loadedSections = Set.empty
                            , showCustomInput = False
                            , customError = Nothing
                          }
                        , fetchStats model.userSlug period
                        )

                _ ->
                    ( { model | customError = Just "Enter two dates separated by a space" }, Cmd.none )

        FilterBy field value ->
            let
                filter =
                    Just { field = field, value = value }

                page =
                    1
            in
            ( { model | activeFilter = filter, activeSearch = Nothing, searchInput = "", offset = 0, activeTab = ListensTab, loading = True }
            , Cmd.batch
                [ fetchListens model.userSlug model.limit 0 filter Nothing
                , Nav.pushUrl model.navKey
                    (buildQuery model.userSlug
                        { page = page
                        , filterField = Just field
                        , filterValue = Just value
                        , search = Nothing
                        , tab = ListensTab
                        }
                    )
                ]
            )

        ClearFilter ->
            ( { model | activeFilter = Nothing, offset = 0, loading = True }
            , Cmd.batch
                [ fetchListens model.userSlug model.limit 0 Nothing model.activeSearch
                , Nav.pushUrl model.navKey
                    (buildQuery model.userSlug
                        { page = 1
                        , filterField = Nothing
                        , filterValue = Nothing
                        , search = model.activeSearch
                        , tab = model.activeTab
                        }
                    )
                ]
            )

        UpdateSearchInput str ->
            ( { model | searchInput = str }, Cmd.none )

        SubmitSearch ->
            let
                q =
                    String.trim model.searchInput
            in
            if String.isEmpty q then
                ( { model | activeSearch = Nothing, offset = 0, loading = True }
                , Cmd.batch
                    [ fetchListens model.userSlug model.limit 0 model.activeFilter Nothing
                    , Nav.pushUrl model.navKey
                        (buildQuery model.userSlug
                            { page = 1
                            , filterField = Maybe.map .field model.activeFilter
                            , filterValue = Maybe.map .value model.activeFilter
                            , search = Nothing
                            , tab = model.activeTab
                            }
                        )
                    ]
                )

            else
                ( { model | activeSearch = Just q, activeFilter = Nothing, offset = 0, loading = True }
                , Cmd.batch
                    [ fetchListens model.userSlug model.limit 0 Nothing (Just q)
                    , Nav.pushUrl model.navKey
                        (buildQuery model.userSlug
                            { page = 1
                            , filterField = Nothing
                            , filterValue = Nothing
                            , search = Just q
                            , tab = model.activeTab
                            }
                        )
                    ]
                )

        ClearSearch ->
            ( { model | searchInput = "", activeSearch = Nothing, offset = 0, loading = True }
            , Cmd.batch
                [ fetchListens model.userSlug model.limit 0 model.activeFilter Nothing
                , Nav.pushUrl model.navKey
                    (buildQuery model.userSlug
                        { page = 1
                        , filterField = Maybe.map .field model.activeFilter
                        , filterValue = Maybe.map .value model.activeFilter
                        , search = Nothing
                        , tab = model.activeTab
                        }
                    )
                ]
            )

        HoverCover idx ->
            ( { model | hoveredCover = Just idx }, Cmd.none )

        UnhoverCover ->
            ( { model | hoveredCover = Nothing }, Cmd.none )

        CoverBackgroundClick ->
            ( { model | hoveredCover = Nothing }, Cmd.none )

        ExpandSection section ->
            ( { model | expandedSections = Set.insert section model.expandedSections }, Cmd.none )

        ShowAllSection section ->
            ( model, fetchSectionData model.userSlug model.statsPeriod section )

        CollapseSection section ->
            ( { model
                | expandedSections = Set.remove section model.expandedSections
                , loadedSections = Set.remove section model.loadedSections
              }
            , Cmd.none
            )

        FetchSimilar artist track ->
            let
                key =
                    similarKey artist track
            in
            if Dict.member key model.similarStates then
                ( { model | similarStates = Dict.remove key model.similarStates }, Cmd.none )

            else
                ( { model | similarStates = Dict.insert key SimilarLoading model.similarStates }
                , fetchSimilarTracks artist track
                )

        FetchSimilarTracks artist track result ->
            let
                key =
                    similarKey artist track

                newStates =
                    case result of
                        Ok tracks ->
                            Dict.insert key (SimilarLoaded tracks) model.similarStates

                        Err err ->
                            Dict.insert key (SimilarError (httpErrorToString err)) model.similarStates
            in
            ( { model | similarStates = newStates }, Cmd.none )

        UpdateRegField field val ->
            let
                m =
                    { model | regError = Nothing, regSubmitted = False }
            in
            ( case field of
                FSlug ->
                    { m | regSlug = val }

                FName ->
                    { m | regName = val }

                FEmail ->
                    { m | regEmail = val }

                FLbUser ->
                    { m | regLbUser = val }

                FLfUser ->
                    { m | regLfUser = val }
            , Cmd.none
            )

        SubmitRegistration ->
            if String.isEmpty (String.trim model.regSlug) || String.isEmpty (String.trim model.regName) || String.isEmpty (String.trim model.regEmail) then
                ( { model | regError = Just "Username, name and email are required" }, Cmd.none )

            else
                ( { model | regSubmitting = True, regError = Nothing }
                , submitRegistration
                    { slug = model.regSlug
                    , name = model.regName
                    , email = model.regEmail
                    , lbUser = model.regLbUser
                    , lfUser = model.regLfUser
                    }
                )

        GotRegistrationResult result ->
            case result of
                Ok () ->
                    ( { model | regSubmitting = False, regSubmitted = True, regError = Nothing }, Cmd.none )

                Err msg_ ->
                    ( { model | regSubmitting = False, regError = Just msg_ }, Cmd.none )

        UpdateAdminTokenInput val ->
            ( { model | adminTokenInput = val }, Cmd.none )

        SaveAdminToken ->
            let
                token =
                    String.trim model.adminTokenInput
            in
            ( { model | adminToken = token, adminError = Nothing }
            , Cmd.batch
                [ Ports.saveAdminToken token
                , if String.isEmpty token then
                    Cmd.none

                  else
                    Cmd.batch [ fetchRegistrations token, fetchUsers token ]
                ]
            )

        FetchRegistrations ->
            ( { model | adminError = Nothing }
            , if String.isEmpty model.adminToken then
                Cmd.none

              else
                fetchRegistrations model.adminToken
            )

        GotRegistrations result ->
            case result of
                Ok regs ->
                    ( { model | registrations = regs, adminError = Nothing }, Cmd.none )

                Err err ->
                    ( { model | adminError = Just (httpErrorToString err) }, Cmd.none )

        ApproveRegistration id ->
            ( model, approveRegistration model.adminToken id )

        DenyRegistration id ->
            ( model, denyRegistration model.adminToken id )

        GotApproveResult result ->
            case result of
                Ok resp ->
                    ( { model | approvedToken = resp.token, adminError = Nothing }
                    , if String.isEmpty model.adminToken then
                        Cmd.none

                      else
                        Cmd.batch [ fetchRegistrations model.adminToken, fetchUsers model.adminToken ]
                    )

                Err err ->
                    ( { model | adminError = Just (httpErrorToString err) }, Cmd.none )

        GotDenyResult result ->
            case result of
                Ok () ->
                    ( model
                    , if String.isEmpty model.adminToken then
                        Cmd.none

                      else
                        fetchRegistrations model.adminToken
                    )

                Err msg_ ->
                    ( { model | adminError = Just msg_ }, Cmd.none )

        FetchUsers ->
            ( { model | adminError = Nothing }
            , if String.isEmpty model.adminToken then
                Cmd.none

              else
                fetchUsers model.adminToken
            )

        GotUsers result ->
            case result of
                Ok users ->
                    ( { model | users = users, adminError = Nothing }, Cmd.none )

                Err err ->
                    ( { model | adminError = Just (httpErrorToString err) }, Cmd.none )

        RequestRemoveUser id ->
            ( { model | confirmingRemoval = Just id }, Cmd.none )

        CancelRemoveUser ->
            ( { model | confirmingRemoval = Nothing }, Cmd.none )

        RemoveUser id ->
            ( { model | confirmingRemoval = Nothing }, removeUser model.adminToken id )

        GotRemoveResult result ->
            case result of
                Ok () ->
                    ( model
                    , if String.isEmpty model.adminToken then
                        Cmd.none

                      else
                        fetchUsers model.adminToken
                    )

                Err msg_ ->
                    ( { model | adminError = Just msg_ }, Cmd.none )


{-| Identify a similar-tracks panel by its content. Row indices shift
whenever a refetch reorders or replaces the current page, so an index would
strand open panels and leak dict entries.
-}
similarKey : String -> String -> String
similarKey artist track =
    artist ++ "\t" ++ track


patchStatSection : String -> List StatsEntry -> Stats -> Stats
patchStatSection section entries stats =
    case section of
        "artist" ->
            { stats | artists = entries }

        "track" ->
            { stats | tracks = entries }

        "genre" ->
            { stats | genres = entries }

        "label" ->
            { stats | labels = entries }

        "year" ->
            { stats | years = entries }

        _ ->
            stats



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ Time.every 30000 Tick
        , Browser.Events.onVisibilityChange VisibilityChanged
        , Browser.Events.onKeyDown escapeKey
        ]


-- | Escape dismisses the zoomed cover, matching the backdrop click.
escapeKey : D.Decoder Msg
escapeKey =
    D.field "key" D.string
        |> D.andThen
            (\key ->
                if key == "Escape" then
                    D.succeed CoverBackgroundClick

                else
                    D.fail "not escape"
            )



-- HTTP
