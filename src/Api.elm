module Api exposing (approveRegistration, denyRegistration, fetchListens, fetchRegistrations, fetchSectionData, fetchSimilarTracks, fetchStats, httpErrorToString, listensDecoder, sectionEntriesDecoder, similarTracksDecoder, statsDecoder, statsUrl, submitRegistration)

import Http
import Json.Decode as D exposing (Decoder)
import Json.Encode as E
import Types exposing (ActiveFilter, ApproveResponse, Listen, Msg(..), Period(..), Registration, SimilarTrack, Stats, StatsEntry)
import Url


fetchListens : String -> Int -> Int -> Maybe ActiveFilter -> Maybe String -> Cmd Msg
fetchListens userSlug limit offset mFilter mSearch =
    let
        filterParams =
            case mFilter of
                Nothing ->
                    ""

                Just { field, value } ->
                    "&filterField=" ++ field ++ "&filterValue=" ++ Url.percentEncode value

        searchParam =
            case mSearch of
                Nothing ->
                    ""

                Just q ->
                    "&search=" ++ Url.percentEncode q

        url =
            "/proxy?user=" ++ userSlug ++ "&limit=" ++ String.fromInt limit ++ "&offset=" ++ String.fromInt offset ++ filterParams ++ searchParam
    in
    Http.get
        { url = url
        , expect = Http.expectJson GotListens listensDecoder
        }


fetchStats : String -> Period -> Cmd Msg
fetchStats userSlug period =
    Http.get
        { url = statsUrl userSlug period Nothing
        , expect = Http.expectJson GotStats statsDecoder
        }


fetchSectionData : String -> Period -> String -> Cmd Msg
fetchSectionData userSlug period section =
    Http.get
        { url = statsUrl userSlug period (Just section)
        , expect = Http.expectJson (GotSectionData section) (sectionEntriesDecoder section)
        }


statsUrl : String -> Period -> Maybe String -> String
statsUrl userSlug period mSection =
    let
        periodPart =
            case period of
                AllTime ->
                    ""

                LastDays n ->
                    "&period=" ++ String.fromInt n

                CustomRange from to ->
                    "&from=" ++ from ++ "&to=" ++ to

        sectionPart =
            case mSection of
                Nothing ->
                    ""

                Just sec ->
                    "&section=" ++ sec
    in
    "/stats?user=" ++ userSlug ++ periodPart ++ sectionPart


fetchSimilarTracks : Int -> String -> String -> Cmd Msg
fetchSimilarTracks idx artist track =
    Http.get
        { url = "/similar?artist=" ++ Url.percentEncode artist ++ "&track=" ++ Url.percentEncode track
        , expect = Http.expectJson (FetchSimilarTracks idx artist track) similarTracksDecoder
        }


submitRegistration : { slug : String, name : String, email : String, lbUser : String, lfUser : String } -> Cmd Msg
submitRegistration f =
    let
        optional key val =
            if String.isEmpty (String.trim val) then
                []

            else
                [ ( key, E.string (String.trim val) ) ]

        body =
            E.object
                ([ ( "slug", E.string (String.trim f.slug) )
                 , ( "name", E.string (String.trim f.name) )
                 , ( "email", E.string (String.trim f.email) )
                 ]
                    ++ optional "listenbrainzUser" f.lbUser
                    ++ optional "lastfmUser" f.lfUser
                )
    in
    Http.post
        { url = "/register"
        , body = Http.jsonBody body
        , expect = expectWhateverWithError GotRegistrationResult
        }


{-| Like Http.expectWhatever, but surfaces the server's plaintext error body.
-}
expectWhateverWithError : (Result String () -> msg) -> Http.Expect msg
expectWhateverWithError toMsg =
    Http.expectStringResponse toMsg <|
        \response ->
            case response of
                Http.GoodStatus_ _ _ ->
                    Ok ()

                Http.BadStatus_ _ errBody ->
                    Err
                        (if String.isEmpty errBody then
                            "Request failed"

                         else
                            errBody
                        )

                Http.BadUrl_ u ->
                    Err ("Bad URL: " ++ u)

                Http.Timeout_ ->
                    Err "Request timed out"

                Http.NetworkError_ ->
                    Err "Network error"


fetchRegistrations : String -> Cmd Msg
fetchRegistrations token =
    Http.request
        { method = "GET"
        , headers = [ Http.header "Authorization" ("Bearer " ++ token) ]
        , url = "/admin/registrations"
        , body = Http.emptyBody
        , expect = Http.expectJson GotRegistrations (D.list registrationDecoder)
        , timeout = Nothing
        , tracker = Nothing
        }


approveRegistration : String -> String -> Cmd Msg
approveRegistration token id =
    Http.request
        { method = "POST"
        , headers = [ Http.header "Authorization" ("Bearer " ++ token) ]
        , url = "/admin/registrations/approve"
        , body = Http.jsonBody (E.object [ ( "id", E.string id ) ])
        , expect = Http.expectJson GotApproveResult approveResponseDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


denyRegistration : String -> String -> Cmd Msg
denyRegistration token id =
    Http.request
        { method = "POST"
        , headers = [ Http.header "Authorization" ("Bearer " ++ token) ]
        , url = "/admin/registrations/deny"
        , body = Http.jsonBody (E.object [ ( "id", E.string id ) ])
        , expect = expectWhateverWithError GotDenyResult
        , timeout = Nothing
        , tracker = Nothing
        }


httpErrorToString : Http.Error -> String
httpErrorToString err =
    case err of
        Http.BadUrl url ->
            "Bad URL: " ++ url

        Http.Timeout ->
            "Request timed out"

        Http.NetworkError ->
            "Network error"

        Http.BadStatus status ->
            "Server error: " ++ String.fromInt status

        Http.BadBody body ->
            "JSON decode error: " ++ body



-- DECODERS


listensDecoder : Decoder (List Listen)
listensDecoder =
    D.at [ "payload", "listens" ] (D.list listenDecoder)


listenDecoder : Decoder Listen
listenDecoder =
    D.map2
        (\meta listenedAt ->
            { trackName = meta.trackName
            , artistName = meta.artistName
            , releaseName = meta.releaseName
            , listenedAt = listenedAt
            , genre = meta.genre
            , label = meta.label
            , releaseMbid = meta.releaseMbid
            , caaReleaseMbid = meta.caaReleaseMbid
            }
        )
        (D.field "track_metadata" trackMetaDecoder)
        (D.maybe (D.field "listened_at" D.int))


type alias TrackMeta =
    { trackName : Maybe String
    , artistName : Maybe String
    , releaseName : Maybe String
    , genre : Maybe String
    , releaseMbid : Maybe String
    , caaReleaseMbid : Maybe String
    , label : Maybe String
    }


trackMetaDecoder : Decoder TrackMeta
trackMetaDecoder =
    D.map7 TrackMeta
        (D.maybe (D.field "track_name" D.string))
        (D.maybe (D.field "artist_name" D.string))
        (D.maybe (D.field "release_name" D.string))
        (D.maybe (D.field "genre" D.string))
        (D.maybe (D.at [ "mbid_mapping", "release_mbid" ] D.string))
        (D.maybe (D.at [ "mbid_mapping", "caa_release_mbid" ] D.string))
        (D.maybe (D.field "label" D.string))


statsDecoder : Decoder Stats
statsDecoder =
    D.map5 Stats
        (D.field "genres" (D.list entryDecoder))
        (D.field "labels" (D.list entryDecoder))
        (D.field "years" (D.list entryDecoder))
        (D.field "artists" (D.list entryDecoder))
        (D.field "tracks" (D.list entryDecoder))


entryDecoder : Decoder StatsEntry
entryDecoder =
    D.map2 StatsEntry
        (D.field "name" D.string)
        (D.field "count" D.int)


sectionEntriesDecoder : String -> Decoder (List StatsEntry)
sectionEntriesDecoder section =
    D.map
        (\stats ->
            case section of
                "artist" ->
                    stats.artists

                "track" ->
                    stats.tracks

                "genre" ->
                    stats.genres

                "label" ->
                    stats.labels

                "year" ->
                    stats.years

                _ ->
                    []
        )
        statsDecoder


similarTracksDecoder : Decoder (List SimilarTrack)
similarTracksDecoder =
    D.at [ "data", "similar_tracks" ] (D.list similarTrackDecoder)


similarTrackDecoder : Decoder SimilarTrack
similarTrackDecoder =
    D.map4 SimilarTrack
        (D.field "artist" D.string)
        (D.field "track" D.string)
        (D.maybe (D.field "score" D.float))
        (D.maybe (D.field "video_uri" D.string))


registrationDecoder : Decoder Registration
registrationDecoder =
    D.map6 Registration
        (D.field "id" D.string)
        (D.field "slug" D.string)
        (D.field "name" D.string)
        (D.field "email" D.string)
        (D.maybe (D.field "listenbrainzUser" D.string))
        (D.maybe (D.field "lastfmUser" D.string))


approveResponseDecoder : Decoder ApproveResponse
approveResponseDecoder =
    D.map2 ApproveResponse
        (D.field "status" D.string)
        (D.maybe (D.field "token" D.string))
