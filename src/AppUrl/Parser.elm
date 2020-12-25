module AppUrl.Parser exposing (urlToViewState)

import Dict
import OpenStack.Types as OSTypes
import Types.Defaults as Defaults
import Types.Types
    exposing
        ( JetstreamCreds
        , JetstreamProvider(..)
        , LoginView(..)
        , NonProjectViewConstructor(..)
        , ProjectViewConstructor(..)
        , ViewState(..)
        )
import Url
import Url.Parser
    exposing
        ( (</>)
        , (<?>)
        , Parser
        , map
        , oneOf
        , parse
        , s
        , string
        )
import Url.Parser.Query as Query


urlToViewState : Maybe String -> Url.Url -> Maybe ViewState
urlToViewState maybePathPrefix url =
    case maybePathPrefix of
        Nothing ->
            parse (oneOf pathParsers) url

        Just pathPrefix ->
            parse (s pathPrefix </> oneOf pathParsers) url


pathParsers : List (Parser (ViewState -> b) b)
pathParsers =
    [ -- Non-project-specific views
      map
        (\creds -> NonProjectView <| Login <| LoginOpenstack creds)
        (let
            queryParser =
                Query.map6
                    OSTypes.OpenstackLogin
                    (Query.string "authurl"
                        |> Query.map (Maybe.withDefault "")
                    )
                    (Query.string "pdomain"
                        |> Query.map (Maybe.withDefault "")
                    )
                    (Query.string "pname"
                        |> Query.map (Maybe.withDefault "")
                    )
                    (Query.string "udomain"
                        |> Query.map (Maybe.withDefault "")
                    )
                    (Query.string "uname"
                        |> Query.map (Maybe.withDefault "")
                    )
                    -- This parses into a blank password, ugly I know
                    (Query.string ""
                        |> Query.map (\_ -> "")
                    )
         in
         s "login" </> s "openstack" <?> queryParser
        )
    , map
        (\creds -> NonProjectView <| Login <| LoginJetstream creds)
        (let
            providerEnumDict =
                Dict.fromList
                    [ ( "iu", IUCloud )
                    , ( "tacc", TACCCloud )
                    , ( "both", BothJetstreamClouds )
                    ]

            queryParser =
                Query.map4
                    JetstreamCreds
                    (Query.enum "provider" providerEnumDict
                        |> Query.map (Maybe.withDefault BothJetstreamClouds)
                    )
                    (Query.string "pname"
                        |> Query.map (Maybe.withDefault "")
                    )
                    (Query.string "taccuname"
                        |> Query.map (Maybe.withDefault "")
                    )
                    -- This parses into a blank password, ugly I know
                    (Query.string ""
                        |> Query.map (\_ -> "")
                    )
         in
         s "login" </> s "jetstream" <?> queryParser
        )
    , map
        (NonProjectView LoginPicker)
        (s "loginpicker")

    -- Not bothering to decode the SelectProjects view, because you can't currently navigate there on a fresh page load and see anything useful
    , map
        (NonProjectView MessageLog)
        (s "msglog")
    , map
        (NonProjectView Settings)
        (s "settings")
    , map
        (NonProjectView <| GetSupport Nothing "")
        (s "getsupport")
    , map
        (NonProjectView HelpAbout)
        (s "helpabout")
    , map
        (\uuid projectViewConstructor -> ProjectView uuid { createPopup = False } <| projectViewConstructor)
        (s "projects" </> string </> oneOf projectViewConstructorParsers)
    ]


projectViewConstructorParsers : List (Parser (ProjectViewConstructor -> b) b)
projectViewConstructorParsers =
    [ map
        (ListImages Defaults.imageListViewParams Defaults.sortTableParams)
        (s "images")
    , map
        (\svrUuid imageName ->
            CreateServerImage svrUuid imageName
        )
        (let
            queryParser =
                Query.string "name"
                    |> Query.map (Maybe.withDefault "")
         in
         s "servers" </> string </> s "image" <?> queryParser
        )
    , map
        (\svrUuid ->
            ServerDetail svrUuid Defaults.serverDetailViewParams
        )
        (s "servers" </> string)
    , map
        (ListProjectServers Defaults.serverListViewParams)
        (s "servers")
    , map
        (\volUuid ->
            VolumeDetail volUuid []
        )
        (s "volumes" </> string)
    , map
        (ListProjectVolumes [])
        (s "volumes")
    , map
        ListQuotaUsage
        (s "quotausage")
    , map
        (\params ->
            CreateServer params
        )
        (let
            maybeBoolEnumDict =
                Dict.fromList
                    [ ( "justtrue", Just True )
                    , ( "justfalse", Just False )
                    , ( "nothing", Nothing )
                    ]

            queryParser =
                Query.map3
                    Defaults.createServerViewParams
                    (Query.string "imageuuid"
                        |> Query.map (Maybe.withDefault "")
                    )
                    (Query.string "imagename"
                        |> Query.map (Maybe.withDefault "")
                    )
                    (Query.enum "deployguac" maybeBoolEnumDict
                        |> Query.map (Maybe.withDefault Nothing)
                    )
         in
         s "createserver" <?> queryParser
        )
    , map
        Defaults.createVolumeView
        (s "createvolume")
    , map
        (\( maybeServerUuid, maybeVolUuid ) ->
            AttachVolumeModal maybeServerUuid maybeVolUuid
        )
        (let
            queryParser =
                Query.map2
                    Tuple.pair
                    (Query.string "serveruuid")
                    (Query.string "voluuid")
         in
         s "attachvol" <?> queryParser
        )
    , map
        (\attachment ->
            MountVolInstructions attachment
        )
        (let
            queryParser =
                Query.map3
                    OSTypes.VolumeAttachment
                    (Query.string "serveruuid"
                        |> Query.map (Maybe.withDefault "")
                    )
                    (Query.string "attachmentuuid"
                        |> Query.map (Maybe.withDefault "")
                    )
                    (Query.string "device"
                        |> Query.map (Maybe.withDefault "")
                    )
         in
         s "attachvolinstructions" <?> queryParser
        )
    ]
