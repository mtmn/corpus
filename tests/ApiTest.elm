module ApiTest exposing (suite)

import Api exposing (listensDecoder, statsDecoder)
import Expect
import Json.Decode as D
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Api decoders"
        [ describe "listensDecoder"
            [ test "decodes a payload with one listen" <|
                \_ ->
                    let
                        json =
                            """
                            {
                                "payload": {
                                    "listens": [
                                        {
                                            "track_metadata": {
                                                "track_name": "Song",
                                                "artist_name": "Artist",
                                                "release_name": "Album",
                                                "genre": "Rock",
                                                "label": "Label",
                                                "mbid_mapping": {
                                                    "release_mbid": "00000000-0000-0000-0000-000000000001",
                                                    "caa_release_mbid": "00000000-0000-0000-0000-000000000002"
                                                }
                                            },
                                            "listened_at": 1700000000
                                        }
                                    ]
                                }
                            }
                            """

                        expected =
                            [ { trackName = Just "Song"
                              , artistName = Just "Artist"
                              , releaseName = Just "Album"
                              , listenedAt = Just 1700000000
                              , genre = Just "Rock"
                              , label = Just "Label"
                              , releaseMbid = Just "00000000-0000-0000-0000-000000000001"
                              , caaReleaseMbid = Just "00000000-0000-0000-0000-000000000002"
                              }
                            ]
                    in
                    Expect.equal (D.decodeString listensDecoder json) (Ok expected)
            , test "handles missing optional fields" <|
                \_ ->
                    let
                        json =
                            """
                            {
                                "payload": {
                                    "listens": [
                                        {
                                            "track_metadata": {},
                                            "listened_at": null
                                        }
                                    ]
                                }
                            }
                            """

                        expected =
                            [ { trackName = Nothing
                              , artistName = Nothing
                              , releaseName = Nothing
                              , listenedAt = Nothing
                              , genre = Nothing
                              , label = Nothing
                              , releaseMbid = Nothing
                              , caaReleaseMbid = Nothing
                              }
                            ]
                    in
                    Expect.equal (D.decodeString listensDecoder json) (Ok expected)
            ]
        , describe "statsDecoder"
            [ test "decodes a stats response" <|
                \_ ->
                    let
                        json =
                            """
                            {
                                "totalScrobbles": 42,
                                "genres": [{"name": "Rock", "count": 10}],
                                "labels": [{"name": "Label", "count": 5}],
                                "years": [{"name": "2024", "count": 20}],
                                "artists": [{"name": "Artist", "count": 15}],
                                "tracks": [{"name": "Song", "count": 7}]
                            }
                            """

                        expected =
                            { totalScrobbles = 42
                            , genres = [ { name = "Rock", count = 10 } ]
                            , labels = [ { name = "Label", count = 5 } ]
                            , years = [ { name = "2024", count = 20 } ]
                            , artists = [ { name = "Artist", count = 15 } ]
                            , tracks = [ { name = "Song", count = 7 } ]
                            }
                    in
                    Expect.equal (D.decodeString statsDecoder json) (Ok expected)
            ]
        ]
