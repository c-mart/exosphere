module Helpers.Interaction exposing (interactionDetails, interactionStatus, interactionStatusWordColor)

import Element
import FeatherIcons
import Helpers.GetterSetters as GetterSetters
import Helpers.Helpers as Helpers
import Helpers.RemoteDataPlusPlus as RDPP
import Helpers.String
import Helpers.Url as UrlHelpers
import OpenStack.Types as OSTypes
import RemoteData
import Style.Helpers as SH
import Style.Types
import Style.Widgets.Icon as Icon
import Time
import Types.Guacamole as GuacTypes
import Types.Interaction as ITypes
import Types.Types
    exposing
        ( Project
        , Server
        , ServerOrigin(..)
        , UserAppProxyHostname
        )
import View.Types


interactionStatus : Project -> Server -> ITypes.Interaction -> View.Types.Context -> Time.Posix -> Maybe UserAppProxyHostname -> ITypes.InteractionStatus
interactionStatus project server interaction context currentTime tlsReverseProxyHostname =
    let
        maybeFloatingIpAddress =
            GetterSetters.getServerFloatingIps project server.osProps.uuid
                |> List.map .address
                |> List.head

        guac : GuacType -> ITypes.InteractionStatus
        guac guacType =
            let
                guacUpstreamPort =
                    49528

                fortyMinMillis =
                    1000 * 60 * 40

                newServer =
                    Helpers.serverLessThanThisOld server currentTime fortyMinMillis

                recentServerEvent =
                    server.events
                        |> RemoteData.withDefault []
                        -- Ignore server events which don't cause a power cycle
                        |> List.filter
                            (\event ->
                                [ "lock", "unlock", "image" ]
                                    |> List.map (\action -> action == event.action)
                                    |> List.any identity
                                    |> not
                            )
                        -- Look for the most recent server event
                        |> List.map .startTime
                        |> List.map Time.posixToMillis
                        |> List.sort
                        |> List.reverse
                        |> List.head
                        -- See if most recent event is recent enough
                        |> Maybe.map
                            (\eventTime ->
                                eventTime > (Time.posixToMillis currentTime - fortyMinMillis)
                            )
                        |> Maybe.withDefault newServer

                connectionStringBase64 =
                    -- Per https://sourceforge.net/p/guacamole/discussion/1110834/thread/fb609070/
                    case guacType of
                        Terminal ->
                            -- printf 'shell\0c\0default' | base64
                            "c2hlbGwAYwBkZWZhdWx0"

                        Desktop ->
                            -- printf 'desktop\0c\0default' | base64
                            "ZGVza3RvcABjAGRlZmF1bHQ="
            in
            case server.exoProps.serverOrigin of
                ServerNotFromExo ->
                    ITypes.Unavailable <|
                        String.join
                            " "
                            [ context.localization.virtualComputer
                                |> Helpers.String.toTitleCase
                            , "not launched from Exosphere"
                            ]

                ServerFromExo exoOriginProps ->
                    case exoOriginProps.guacamoleStatus of
                        GuacTypes.NotLaunchedWithGuacamole ->
                            if exoOriginProps.exoServerVersion < 3 then
                                ITypes.Unavailable <|
                                    String.join " "
                                        [ context.localization.virtualComputer
                                            |> Helpers.String.toTitleCase
                                        , "was created with an older version of Exosphere"
                                        ]

                            else
                                ITypes.Unavailable <|
                                    String.join " "
                                        [ context.localization.virtualComputer
                                            |> Helpers.String.toTitleCase
                                        , "was deployed with Guacamole support de-selected"
                                        ]

                        GuacTypes.LaunchedWithGuacamole guacProps ->
                            if not guacProps.vncSupported && (guacType == Desktop) then
                                ITypes.Unavailable <|
                                    String.join " "
                                        [ context.localization.graphicalDesktopEnvironment
                                            |> Helpers.String.toTitleCase
                                        , "was not enabled when"
                                        , context.localization.virtualComputer
                                            |> Helpers.String.toTitleCase
                                        , "was deployed"
                                        ]

                            else
                                case guacProps.authToken.data of
                                    RDPP.DoHave token _ ->
                                        case ( tlsReverseProxyHostname, maybeFloatingIpAddress ) of
                                            ( Just proxyHostname, Just floatingIp ) ->
                                                ITypes.Ready <|
                                                    UrlHelpers.buildProxyUrl
                                                        proxyHostname
                                                        floatingIp
                                                        guacUpstreamPort
                                                        ("/guacamole/#/client/" ++ connectionStringBase64 ++ "?token=" ++ token)
                                                        False

                                            ( Nothing, _ ) ->
                                                ITypes.Unavailable "Cannot find TLS-terminating reverse proxy server"

                                            ( _, Nothing ) ->
                                                ITypes.Unavailable <|
                                                    String.join " "
                                                        [ context.localization.virtualComputer
                                                            |> Helpers.String.toTitleCase
                                                        , "does not have a"
                                                        , context.localization.floatingIpAddress
                                                        ]

                                    RDPP.DontHave ->
                                        if recentServerEvent then
                                            ITypes.Unavailable <|
                                                String.join " "
                                                    [ context.localization.virtualComputer
                                                        |> Helpers.String.toTitleCase
                                                    , "is still booting or Guacamole is still deploying, check back in a few minutes"
                                                    ]

                                        else
                                            case
                                                ( tlsReverseProxyHostname
                                                , maybeFloatingIpAddress
                                                , GetterSetters.getServerExouserPassword server.osProps.details
                                                )
                                            of
                                                ( Nothing, _, _ ) ->
                                                    ITypes.Error "Cannot find TLS-terminating reverse proxy server"

                                                ( _, Nothing, _ ) ->
                                                    ITypes.Error <|
                                                        String.join " "
                                                            [ context.localization.virtualComputer
                                                                |> Helpers.String.toTitleCase
                                                            , "does not have a"
                                                            , context.localization.floatingIpAddress
                                                            ]

                                                ( _, _, Nothing ) ->
                                                    ITypes.Error <|
                                                        String.join " "
                                                            [ "Cannot find"
                                                            , context.localization.virtualComputer
                                                            , "password to authenticate"
                                                            ]

                                                ( Just _, Just _, Just _ ) ->
                                                    case guacProps.authToken.refreshStatus of
                                                        RDPP.Loading ->
                                                            ITypes.Loading

                                                        RDPP.NotLoading maybeErrorTuple ->
                                                            -- If deployment is complete but we can't get a token, show error to user
                                                            case maybeErrorTuple of
                                                                Nothing ->
                                                                    -- This is a slight misrepresentation; we haven't requested
                                                                    -- a token yet but orchestration code will make request soon
                                                                    ITypes.Loading

                                                                Just ( httpError, _ ) ->
                                                                    ITypes.Error
                                                                        ("Exosphere tried to authenticate to the Guacamole API, and received this error: "
                                                                            ++ Helpers.httpErrorToString httpError
                                                                        )
    in
    case server.osProps.details.openstackStatus of
        OSTypes.ServerBuilding ->
            ITypes.Unavailable <|
                String.join " "
                    [ context.localization.virtualComputer
                        |> Helpers.String.toTitleCase
                    , "is still building"
                    ]

        OSTypes.ServerActive ->
            case interaction of
                ITypes.GuacTerminal ->
                    guac Terminal

                ITypes.GuacDesktop ->
                    guac Desktop

                ITypes.NativeSSH ->
                    case maybeFloatingIpAddress of
                        Nothing ->
                            ITypes.Unavailable <|
                                String.join " "
                                    [ context.localization.virtualComputer
                                        |> Helpers.String.toTitleCase
                                    , "does not have a"
                                    , context.localization.floatingIpAddress
                                    ]

                        Just floatingIp ->
                            ITypes.Ready <| "exouser@" ++ floatingIp

                ITypes.Console ->
                    case server.osProps.consoleUrl of
                        RemoteData.NotAsked ->
                            ITypes.Unavailable "Console URL is not queried yet"

                        RemoteData.Loading ->
                            ITypes.Loading

                        RemoteData.Failure httpErrorWithBody ->
                            ITypes.Error ("Exosphere requested a console URL and got the following error: " ++ Helpers.httpErrorToString httpErrorWithBody.error)

                        RemoteData.Success consoleUrl ->
                            ITypes.Ready consoleUrl

        _ ->
            ITypes.Unavailable <|
                String.join " "
                    [ context.localization.virtualComputer
                        |> Helpers.String.toTitleCase
                    , "is not active"
                    ]


interactionStatusWordColor : Style.Types.ExoPalette -> ITypes.InteractionStatus -> ( String, Element.Color )
interactionStatusWordColor palette status =
    case status of
        ITypes.Unavailable _ ->
            ( "Unavailable", SH.toElementColor palette.muted )

        ITypes.Loading ->
            ( "Loading", SH.toElementColor palette.warn )

        ITypes.Ready _ ->
            ( "Ready", SH.toElementColor palette.readyGood )

        ITypes.Warn _ _ ->
            ( "Warning", SH.toElementColor palette.warn )

        ITypes.Error _ ->
            ( "Error", SH.toElementColor palette.error )

        ITypes.Hidden ->
            ( "Hidden", SH.toElementColor palette.muted )


interactionDetails : ITypes.Interaction -> View.Types.Context -> ITypes.InteractionDetails msg
interactionDetails interaction context =
    case interaction of
        ITypes.GuacTerminal ->
            ITypes.InteractionDetails
                (context.localization.commandDrivenTextInterface
                    |> Helpers.String.toTitleCase
                )
                (String.concat
                    [ "Get a terminal session to your "
                    , context.localization.virtualComputer
                    , ". Pro tip, press Ctrl+Alt+Shift inside the terminal window to show a graphical file upload/download tool!"
                    ]
                )
                (\_ _ -> FeatherIcons.terminal |> FeatherIcons.toHtml [] |> Element.html)
                ITypes.UrlInteraction

        ITypes.GuacDesktop ->
            ITypes.InteractionDetails
                (Helpers.String.toTitleCase context.localization.graphicalDesktopEnvironment)
                (String.concat
                    [ "Interact with your "
                    , context.localization.virtualComputer
                    , "'s desktop environment"
                    ]
                )
                (\_ _ -> FeatherIcons.monitor |> FeatherIcons.toHtml [] |> Element.html)
                ITypes.UrlInteraction

        ITypes.NativeSSH ->
            ITypes.InteractionDetails
                "Native SSH"
                "Advanced feature: use your computer's native SSH client to get a command-line session with extra capabilities"
                (\_ _ -> FeatherIcons.terminal |> FeatherIcons.toHtml [] |> Element.html)
                ITypes.TextInteraction

        ITypes.Console ->
            ITypes.InteractionDetails
                "Console"
                (String.join " "
                    [ "Advanced feature: Launching the console is like connecting a screen, mouse, and keyboard to your"
                    , context.localization.virtualComputer
                    , "(useful for troubleshooting if the Web Terminal isn't working)"
                    ]
                )
                Icon.console
                ITypes.UrlInteraction


type GuacType
    = Terminal
    | Desktop
