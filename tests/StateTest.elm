module StateTest exposing (suite)

import Expect
import State exposing (parsePage, parsePageParam)
import Test exposing (Test, describe, test)
import Types exposing (Page(..))
import Url


url : String -> Url.Url
url raw =
    Maybe.withDefault (Url.Url Url.Http "example.com" Nothing "" Nothing Nothing) (Url.fromString raw)


suite : Test
suite =
    describe "State URL helpers"
        [ describe "parsePage"
            [ test "/register resolves to RegisterPage" <|
                \_ ->
                    Expect.equal (parsePage (url "http://example.com/register")) RegisterPage
            , test "/admin resolves to AdminPage" <|
                \_ ->
                    Expect.equal (parsePage (url "http://example.com/admin")) AdminPage
            , test "/ resolves to MainPage" <|
                \_ ->
                    Expect.equal (parsePage (url "http://example.com/")) MainPage
            , test "/u/slug resolves to MainPage" <|
                \_ ->
                    Expect.equal (parsePage (url "http://example.com/u/slug")) MainPage
            ]
        , describe "parsePageParam"
            [ test "defaults to page 1" <|
                \_ ->
                    Expect.equal (parsePageParam (url "http://example.com/")) 1
            , test "reads page query parameter" <|
                \_ ->
                    Expect.equal (parsePageParam (url "http://example.com/?page=4")) 4
            , test "reads page query for user pages" <|
                \_ ->
                    Expect.equal (parsePageParam (url "http://example.com/u/slug?page=7")) 7
            , test "ignores invalid page values" <|
                \_ ->
                    Expect.equal (parsePageParam (url "http://example.com/?page=xyz")) 1
            ]
        ]
