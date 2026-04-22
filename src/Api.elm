module Api exposing (fetchListens, fetchSectionData, fetchSimilarTracks, fetchStats, httpErrorToString, listensDecoder, sectionEntriesDecoder, similarTracksDecoder, statsDecoder, statsUrl)

import Http
import Json.Decode as D exposing (Decoder)
import Types exposing (ActiveFilter, Listen, Msg(..), Period(..), SimilarTrack, Stats, StatsEntry)
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


fetchSimilarTracks : String -> String -> Cmd Msg
fetchSimilarTracks artist track =
    Http.get
        { url = "/similar?artist=" ++ Url.percentEncode artist ++ "&track=" ++ Url.percentEncode track
        , expect = Http.expectJson (FetchSimilarTracks artist track) similarTracksDecoder
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
