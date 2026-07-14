module State exposing (init, subscriptions, update)

import Api exposing (approveRegistration, denyRegistration, fetchListens, fetchRegistrations, fetchSectionData, fetchSimilarTracks, fetchStats, fetchUsers, httpErrorToString, removeUser, submitRegistration)
import Browser
import Browser.Navigation as Nav
import Dict
import Ports
import Set
import Task
import Time
import Types exposing (Flags, Model, Msg(..), Page(..), Period(..), RegField(..), SimilarState(..), Stats, StatsEntry, Tab(..))
import Url
import Url.Parser exposing ((</>), (<?>))
import Url.Parser.Query as Query


init : Flags -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init flags url navKey =
    let
        pageNum =
            parsePageParam url

        offset =
            max 0 ((pageNum - 1) * 25)

        page =
            parsePage url
    in
    ( { navKey = navKey
      , listens = []
      , stats = Nothing
      , error = Nothing
      , loading = True
      , currentTime = Nothing
      , failedCovers = Set.empty
      , hoveredCover = Nothing
      , expandedSections = Set.empty
      , loadedSections = Set.empty
      , offset = offset
      , limit = 25
      , activeTab = ListensTab
      , activeFilter = Nothing
      , statsPeriod = AllTime
      , customInput = ""
      , showCustomInput = False
      , customError = Nothing
      , userSlug = flags.userSlug
      , similarStates = Dict.empty
      , allUsers = flags.allUsers
      , searchInput = ""
      , activeSearch = Nothing
      , tabsVisible = True
      , page = page
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
                [ fetchListens flags.userSlug 25 offset Nothing Nothing
                , Task.perform GotTime Time.now
                ]
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


parsePageParam : Url.Url -> Int
parsePageParam url =
    let
        pageParser =
            Url.Parser.oneOf
                [ Url.Parser.top <?> Query.int "page"
                , (Url.Parser.s "u" </> Url.Parser.string <?> Query.int "page") |> Url.Parser.map (\_ p -> p)
                ]
    in
    Url.Parser.parse pageParser url
        |> Maybe.andThen identity
        |> Maybe.withDefault 1



-- MSG


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UrlRequested urlRequest ->
            case urlRequest of
                Browser.Internal url ->
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

                        pageNum =
                            parsePageParam url

                        targetOffset =
                            max 0 ((pageNum - 1) * model.limit)

                        isNaked =
                            url.query == Nothing

                        userChanged =
                            newUserSlug /= model.userSlug

                        needsCleanStart =
                            userChanged || isNaked

                        finalFilter =
                            if needsCleanStart then
                                Nothing

                            else
                                model.activeFilter

                        finalSearch =
                            if needsCleanStart then
                                Nothing

                            else
                                model.activeSearch

                        finalOffset =
                            if needsCleanStart then
                                0

                            else
                                targetOffset
                    in
                    if model.page /= MainPage || userChanged || model.offset /= finalOffset || model.activeFilter /= finalFilter || model.activeSearch /= finalSearch then
                        let
                            newModel =
                                { model
                                    | userSlug = newUserSlug
                                    , offset = finalOffset
                                    , activeFilter = finalFilter
                                    , activeSearch = finalSearch
                                    , searchInput =
                                        if needsCleanStart then
                                            ""

                                        else
                                            model.searchInput
                                    , activeTab = ListensTab
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
                        , fetchListens newUserSlug model.limit finalOffset finalFilter finalSearch
                        )

                    else
                        ( { model | activeTab = ListensTab, page = MainPage }, Cmd.none )

        Tick time ->
            if model.page == MainPage && not model.loading then
                ( { model | currentTime = Just time, loading = True }
                , fetchListens model.userSlug model.limit model.offset model.activeFilter model.activeSearch
                )

            else
                ( { model | currentTime = Just time }, Cmd.none )

        GotTime time ->
            ( { model | currentTime = Just time }, Cmd.none )

        GotListens result ->
            let
                newModel =
                    case result of
                        Err err ->
                            { model | loading = False, error = Just (httpErrorToString err) }

                        Ok listens ->
                            { model | loading = False, listens = listens, error = Nothing }
            in
            ( newModel, Task.perform GotTime Time.now )

        GotStats result ->
            case result of
                Err err ->
                    ( { model | error = Just (httpErrorToString err) }, Cmd.none )

                Ok stats ->
                    ( { model | stats = Just stats }, Cmd.none )

        GotSectionData section result ->
            case result of
                Err err ->
                    ( { model | error = Just (httpErrorToString err) }, Cmd.none )

                Ok entries ->
                    ( { model
                        | expandedSections = Set.insert section model.expandedSections
                        , loadedSections = Set.insert section model.loadedSections
                        , stats = Maybe.map (patchStatSection section entries) model.stats
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

                prefix =
                    if String.isEmpty model.userSlug then
                        "/"

                    else
                        "/u/" ++ model.userSlug
            in
            ( { model | offset = newOffset, loading = True }
            , Cmd.batch
                [ fetchListens model.userSlug model.limit newOffset model.activeFilter model.activeSearch
                , Nav.pushUrl model.navKey (prefix ++ "?page=" ++ String.fromInt page)
                ]
            )

        PrevPage ->
            let
                newOffset =
                    max 0 (model.offset - model.limit)

                page =
                    newOffset // model.limit + 1

                prefix =
                    if String.isEmpty model.userSlug then
                        "/"

                    else
                        "/u/" ++ model.userSlug
            in
            ( { model | offset = newOffset, loading = True }
            , Cmd.batch
                [ fetchListens model.userSlug model.limit newOffset model.activeFilter model.activeSearch
                , Nav.pushUrl model.navKey (prefix ++ "?page=" ++ String.fromInt page)
                ]
            )

        SwitchTab tab ->
            ( { model | activeTab = tab }
            , case tab of
                StatsTab ->
                    if model.stats == Nothing then
                        fetchStats model.userSlug model.statsPeriod

                    else
                        Cmd.none

                ListensTab ->
                    Cmd.none

                AboutTab ->
                    Cmd.none
            )

        ToggleTabs ->
            ( { model | tabsVisible = not model.tabsVisible }, Cmd.none )

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

                prefix =
                    if String.isEmpty model.userSlug then
                        "/"

                    else
                        "/u/" ++ model.userSlug
            in
            ( { model | activeFilter = filter, activeSearch = Nothing, searchInput = "", offset = 0, activeTab = ListensTab, loading = True }
            , Cmd.batch
                [ fetchListens model.userSlug model.limit 0 filter Nothing
                , Nav.pushUrl model.navKey (prefix ++ "?page=1")
                ]
            )

        ClearFilter ->
            let
                prefix =
                    if String.isEmpty model.userSlug then
                        "/"

                    else
                        "/u/" ++ model.userSlug
            in
            ( { model | activeFilter = Nothing, offset = 0, loading = True }
            , Cmd.batch
                [ fetchListens model.userSlug model.limit 0 Nothing model.activeSearch
                , Nav.pushUrl model.navKey (prefix ++ "?page=1")
                ]
            )

        UpdateSearchInput str ->
            ( { model | searchInput = str }, Cmd.none )

        SubmitSearch ->
            let
                q =
                    String.trim model.searchInput

                prefix =
                    if String.isEmpty model.userSlug then
                        "/"

                    else
                        "/u/" ++ model.userSlug
            in
            if String.isEmpty q then
                ( { model | activeSearch = Nothing, offset = 0, loading = True }
                , Cmd.batch
                    [ fetchListens model.userSlug model.limit 0 Nothing Nothing
                    , Nav.pushUrl model.navKey (prefix ++ "?page=1")
                    ]
                )

            else
                ( { model | activeSearch = Just q, activeFilter = Nothing, offset = 0, loading = True }
                , Cmd.batch
                    [ fetchListens model.userSlug model.limit 0 Nothing (Just q)
                    , Nav.pushUrl model.navKey (prefix ++ "?page=1")
                    ]
                )

        ClearSearch ->
            let
                prefix =
                    if String.isEmpty model.userSlug then
                        "/"

                    else
                        "/u/" ++ model.userSlug
            in
            ( { model | searchInput = "", activeSearch = Nothing, offset = 0, loading = True }
            , Cmd.batch
                [ fetchListens model.userSlug model.limit 0 Nothing Nothing
                , Nav.pushUrl model.navKey (prefix ++ "?page=1")
                ]
            )

        HoverCover idx ->
            ( { model | hoveredCover = Just idx }, Cmd.none )

        UnhoverCover ->
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

        FetchSimilar idx artist track ->
            let
                key =
                    String.fromInt idx ++ "\t" ++ artist ++ "\t" ++ track
            in
            if Dict.member key model.similarStates then
                ( { model | similarStates = Dict.remove key model.similarStates }, Cmd.none )

            else
                ( { model | similarStates = Dict.insert key SimilarLoading model.similarStates }
                , fetchSimilarTracks idx artist track
                )

        FetchSimilarTracks idx artist track result ->
            let
                key =
                    String.fromInt idx ++ "\t" ++ artist ++ "\t" ++ track

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
    Time.every 30000 Tick



-- HTTP
