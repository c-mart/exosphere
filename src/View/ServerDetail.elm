module View.ServerDetail exposing (serverDetail)

import DateFormat.Relative
import Dict
import Element
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import FeatherIcons
import Helpers.GetterSetters as GetterSetters
import Helpers.Helpers as Helpers
import Helpers.Interaction as IHelpers
import Helpers.RemoteDataPlusPlus as RDPP
import Helpers.String
import Helpers.Time
import OpenStack.ServerActions as ServerActions
import OpenStack.ServerNameValidator exposing (serverNameValidator)
import OpenStack.Types as OSTypes
import RemoteData
import Style.Helpers as SH
import Style.Widgets.CopyableText exposing (copyableText)
import Style.Widgets.Icon as Icon
import Style.Widgets.IconButton
import Style.Widgets.ToggleTip
import Time
import Types.Interaction as ITypes
import Types.Types
    exposing
        ( AssignFloatingIpViewParams
        , FloatingIpOption(..)
        , IPInfoLevel(..)
        , Msg(..)
        , NonProjectViewConstructor(..)
        , PasswordVisibility(..)
        , Project
        , ProjectIdentifier
        , ProjectSpecificMsgConstructor(..)
        , ProjectViewConstructor(..)
        , Server
        , ServerDetailViewParams
        , ServerOrigin(..)
        , ServerSpecificMsgConstructor(..)
        , UserAppProxyHostname
        , ViewState(..)
        )
import View.Helpers as VH
import View.ResourceUsage
import View.Types
import Widget
import Widget.Style.Material


serverDetail : View.Types.Context -> Project -> ( Time.Posix, Time.Zone ) -> ServerDetailViewParams -> OSTypes.ServerUuid -> Element.Element Msg
serverDetail context project currentTimeAndZone serverDetailViewParams serverUuid =
    {- Attempt to look up a given server UUID; if a Server type is found, call rendering function serverDetail_ -}
    case GetterSetters.serverLookup project serverUuid of
        Just server ->
            serverDetail_ context project currentTimeAndZone serverDetailViewParams server

        Nothing ->
            Element.text <|
                String.join " "
                    [ "No"
                    , context.localization.virtualComputer
                    , "found"
                    ]


serverDetail_ : View.Types.Context -> Project -> ( Time.Posix, Time.Zone ) -> ServerDetailViewParams -> Server -> Element.Element Msg
serverDetail_ context project currentTimeAndZone serverDetailViewParams server =
    {- Render details of a server type and associated resources (e.g. volumes) -}
    let
        details =
            server.osProps.details

        updateViewParams : ServerDetailViewParams -> Msg
        updateViewParams newViewParams =
            ProjectMsg project.auth.project.uuid <|
                SetProjectView <|
                    ServerDetail server.osProps.uuid newViewParams

        creatorName =
            case server.exoProps.serverOrigin of
                ServerFromExo exoOriginProps ->
                    case exoOriginProps.exoCreatorUsername of
                        Just creatorName_ ->
                            creatorName_

                        Nothing ->
                            "unknown user"

                _ ->
                    "unknown user"

        flavorText =
            GetterSetters.flavorLookup project details.flavorUuid
                |> Maybe.map .name
                |> Maybe.withDefault ("Unknown " ++ context.localization.virtualComputerHardwareConfig)

        imageText =
            let
                maybeImageName =
                    GetterSetters.imageLookup
                        project
                        details.imageUuid
                        |> Maybe.map .name

                maybeVolBackedImageName =
                    let
                        vols =
                            RemoteData.withDefault [] project.volumes
                    in
                    Helpers.getBootVol vols server.osProps.uuid
                        |> Maybe.andThen .imageMetadata
                        |> Maybe.map .name
            in
            case maybeImageName of
                Just name ->
                    name

                Nothing ->
                    case maybeVolBackedImageName of
                        Just name_ ->
                            name_

                        Nothing ->
                            "N/A"

        serverNameViewPlain =
            Element.row
                [ Element.spacing 10 ]
                [ Element.text server.osProps.name
                , Widget.iconButton
                    (SH.materialStyle context.palette).button
                    { text = "Edit"
                    , icon =
                        FeatherIcons.edit3
                            |> FeatherIcons.withSize 16
                            |> FeatherIcons.toHtml []
                            |> Element.html
                            |> Element.el []
                    , onPress =
                        Just
                            (updateViewParams
                                { serverDetailViewParams
                                    | serverNamePendingConfirmation = Just server.osProps.name
                                }
                            )
                    }
                ]

        serverNameViewEdit =
            let
                invalidNameReasons =
                    serverNameValidator
                        (Just context.localization.virtualComputer)
                        (serverDetailViewParams.serverNamePendingConfirmation
                            |> Maybe.withDefault ""
                        )

                renderInvalidNameReasons =
                    case invalidNameReasons of
                        Just reasons ->
                            List.map Element.text reasons
                                |> List.map List.singleton
                                |> List.map (Element.paragraph [])
                                |> Element.column
                                    [ Font.color (SH.toElementColor context.palette.error)
                                    , Font.size 14
                                    , Element.alignRight
                                    , Element.moveDown 6
                                    , Background.color (SH.toElementColorWithOpacity context.palette.surface 0.9)
                                    , Element.spacing 10
                                    , Element.padding 10
                                    , Border.rounded 4
                                    , Border.shadow
                                        { blur = 10
                                        , color = SH.toElementColorWithOpacity context.palette.muted 0.2
                                        , offset = ( 0, 2 )
                                        , size = 1
                                        }
                                    ]

                        Nothing ->
                            Element.none

                rowStyle =
                    { containerRow =
                        [ Element.spacing 8
                        , Element.width Element.fill
                        ]
                    , element = []
                    , ifFirst = [ Element.width <| Element.minimum 200 <| Element.fill ]
                    , ifLast = []
                    , otherwise = []
                    }

                saveOnPress =
                    case ( invalidNameReasons, serverDetailViewParams.serverNamePendingConfirmation ) of
                        ( Nothing, Just validName ) ->
                            Just
                                (ProjectMsg project.auth.project.uuid <|
                                    ServerMsg server.osProps.uuid <|
                                        RequestSetServerName validName
                                )

                        ( _, _ ) ->
                            Nothing
            in
            Widget.row
                rowStyle
                [ Element.el
                    [ Element.below renderInvalidNameReasons
                    ]
                    (Widget.textInput (Widget.Style.Material.textInput (SH.toMaterialPalette context.palette))
                        { chips = []
                        , text = serverDetailViewParams.serverNamePendingConfirmation |> Maybe.withDefault ""
                        , placeholder =
                            Just
                                (Input.placeholder
                                    []
                                    (Element.text <|
                                        String.join " "
                                            [ "My"
                                            , context.localization.virtualComputer
                                                |> Helpers.String.toTitleCase
                                            ]
                                    )
                                )
                        , label = "Name"
                        , onChange =
                            \n ->
                                updateViewParams
                                    { serverDetailViewParams
                                        | serverNamePendingConfirmation = Just n
                                    }
                        }
                    )
                , Widget.iconButton
                    (SH.materialStyle context.palette).button
                    { text = "Save"
                    , icon =
                        FeatherIcons.save
                            |> FeatherIcons.withSize 16
                            |> FeatherIcons.toHtml []
                            |> Element.html
                            |> Element.el []
                    , onPress =
                        saveOnPress
                    }
                , Widget.iconButton
                    (SH.materialStyle context.palette).button
                    { text = "Cancel"
                    , icon =
                        FeatherIcons.xCircle
                            |> FeatherIcons.withSize 16
                            |> FeatherIcons.toHtml []
                            |> Element.html
                            |> Element.el []
                    , onPress =
                        Just
                            (updateViewParams
                                { serverDetailViewParams
                                    | serverNamePendingConfirmation = Nothing
                                }
                            )
                    }
                ]

        serverNameView =
            case serverDetailViewParams.serverNamePendingConfirmation of
                Just _ ->
                    serverNameViewEdit

                Nothing ->
                    serverNameViewPlain

        ( dualColumn, columnWidth, chartsWidthPx ) =
            if context.windowSize.width < 1402 then
                ( False, Element.fill, context.windowSize.width - 250 )

            else
                let
                    colWidthPx =
                        (context.windowSize.width - 220) // 2
                in
                ( True, colWidthPx |> Element.px, colWidthPx - 30 )

        firstColumnContents : List (Element.Element Msg)
        firstColumnContents =
            [ Element.row
                (VH.heading2 context.palette ++ [ Element.spacing 10 ])
                [ FeatherIcons.server |> FeatherIcons.toHtml [] |> Element.html |> Element.el []
                , Element.text
                    (context.localization.virtualComputer
                        |> Helpers.String.toTitleCase
                    )
                , serverNameView
                ]
            , passwordVulnWarning context server
            , Element.el
                [ Element.paddingXY 0 5
                ]
              <|
                VH.createdAgoByFrom
                    context
                    (Tuple.first currentTimeAndZone)
                    details.created
                    (Just ( "user", creatorName ))
                    (Just ( context.localization.staticRepresentationOfBlockDeviceContents, imageText ))
                    serverDetailViewParams.showCreatedTimeToggleTip
                    (updateViewParams
                        { serverDetailViewParams
                            | showCreatedTimeToggleTip = not serverDetailViewParams.showCreatedTimeToggleTip
                        }
                    )
            , VH.compactKVRow "Status" (serverStatus context project.auth.project.uuid serverDetailViewParams server)
            , VH.compactKVRow "UUID" <| copyableText context.palette [] server.osProps.uuid
            , VH.compactKVRow
                (Helpers.String.toTitleCase context.localization.virtualComputerHardwareConfig)
                (Element.text flavorText)
            , VH.compactKVRow
                (String.join " "
                    [ context.localization.pkiPublicKeyForSsh
                        |> Helpers.String.toTitleCase
                    , "Name"
                    ]
                )
                (Element.text (Maybe.withDefault "(none)" details.keypairName))
            , VH.compactKVRow "IP addresses"
                (renderIpAddresses
                    context
                    project
                    server
                    serverDetailViewParams
                )
            , Element.el (VH.heading3 context.palette)
                (Element.text <|
                    String.concat
                        [ context.localization.blockDevice
                            |> Helpers.String.pluralize
                            |> Helpers.String.toTitleCase
                        , " Attached"
                        ]
                )
            , serverVolumes context project server
            , case GetterSetters.getVolsAttachedToServer project server of
                [] ->
                    Element.none

                _ ->
                    Element.paragraph [ Font.size 11 ] <|
                        [ Element.text <|
                            String.join
                                " "
                                [ "* "
                                , context.localization.blockDevice
                                    |> Helpers.String.toTitleCase
                                , "will only be automatically formatted/mounted on operating systems which use systemd 236 or newer (e.g. Ubuntu 18.04, CentOS 8)."
                                ]
                        ]
            , if
                not <|
                    List.member
                        server.osProps.details.openstackStatus
                        [ OSTypes.ServerShelved
                        , OSTypes.ServerShelvedOffloaded
                        , OSTypes.ServerError
                        , OSTypes.ServerSoftDeleted
                        , OSTypes.ServerBuilding
                        ]
              then
                Widget.textButton
                    (SH.materialStyle context.palette).button
                    { text = "Attach " ++ context.localization.blockDevice
                    , onPress =
                        Just <|
                            ProjectMsg project.auth.project.uuid <|
                                SetProjectView <|
                                    AttachVolumeModal
                                        (Just server.osProps.uuid)
                                        Nothing
                    }

              else
                Element.none
            , Element.el (VH.heading2 context.palette) (Element.text "Interactions")
            , interactions
                context
                project
                server
                (Tuple.first currentTimeAndZone)
                (VH.userAppProxyLookup context project)
                serverDetailViewParams
            , Element.el (VH.heading3 context.palette) (Element.text "Password")
            , serverPassword context project.auth.project.uuid serverDetailViewParams server
            ]

        secondColumnContents : List (Element.Element Msg)
        secondColumnContents =
            List.concat
                [ [ Element.el (VH.heading3 context.palette) (Element.text "Actions")
                  , viewServerActions context project serverDetailViewParams server
                  , serverEventHistory
                        context
                        (Tuple.first currentTimeAndZone)
                        server.events
                  ]
                , if details.openstackStatus == OSTypes.ServerActive then
                    [ Element.el (VH.heading3 context.palette) (Element.text "System Resource Usage")
                    , resourceUsageCharts context chartsWidthPx currentTimeAndZone server
                    ]

                  else
                    []
                ]
    in
    if dualColumn then
        let
            columnAttributes =
                VH.exoColumnAttributes
                    ++ [ Element.alignTop
                       , Element.centerX
                       , Element.width columnWidth
                       ]
        in
        Element.row [ Element.width Element.fill, Element.spacing 5 ]
            [ Element.column
                columnAttributes
                firstColumnContents
            , Element.column
                columnAttributes
                secondColumnContents
            ]

    else
        Element.column
            (VH.exoColumnAttributes ++ [ Element.width Element.fill ])
            (List.append firstColumnContents secondColumnContents)


passwordVulnWarning : View.Types.Context -> Server -> Element.Element Msg
passwordVulnWarning context server =
    case server.exoProps.serverOrigin of
        ServerNotFromExo ->
            Element.none

        ServerFromExo serverFromExoProps ->
            if serverFromExoProps.exoServerVersion < 1 then
                Element.paragraph
                    [ Font.color (SH.toElementColor context.palette.error) ]
                    [ Element.text <|
                        String.join " "
                            [ "Warning: this"
                            , context.localization.virtualComputer
                            , "was created with an older version of Exosphere which left the opportunity for unprivileged processes running on the"
                            , context.localization.virtualComputer
                            , "to query the instance metadata service and determine the password for exouser (who is a sudoer). This represents a "
                            ]
                    , VH.browserLink
                        context
                        "https://en.wikipedia.org/wiki/Privilege_escalation"
                        (View.Types.BrowserLinkTextLabel "privilege escalation vulnerability")
                    , Element.text <|
                        String.join " "
                            [ ". If you have used this"
                            , context.localization.virtualComputer
                            , "for anything important or sensitive, consider rotating the password for exouser, or building a new"
                            , context.localization.virtualComputer
                            , "and moving to that one instead of this one. For more information, see "
                            ]
                    , VH.browserLink
                        context
                        "https://gitlab.com/exosphere/exosphere/issues/284"
                        (View.Types.BrowserLinkTextLabel "issue #284")
                    , Element.text " on the Exosphere GitLab project."
                    ]

            else
                Element.none


serverStatus : View.Types.Context -> ProjectIdentifier -> ServerDetailViewParams -> Server -> Element.Element Msg
serverStatus context projectId serverDetailViewParams server =
    let
        details =
            server.osProps.details

        statusBadge =
            VH.serverStatusBadge context.palette server

        lockStatus : OSTypes.ServerLockStatus -> Element.Element Msg
        lockStatus lockStatus_ =
            case lockStatus_ of
                OSTypes.ServerLocked ->
                    Icon.lock (SH.toElementColor context.palette.on.background) 28

                OSTypes.ServerUnlocked ->
                    Icon.lockOpen (SH.toElementColor context.palette.on.background) 28

        verboseStatusToggleTip =
            let
                friendlyOpenstackStatus : OSTypes.ServerStatus -> String
                friendlyOpenstackStatus osStatus =
                    OSTypes.serverStatusToString osStatus
                        |> String.dropLeft 6

                friendlyPowerState =
                    OSTypes.serverPowerStateToString details.powerState
                        |> String.dropLeft 5

                contents =
                    -- TODO nicer layout here?
                    Element.column []
                        [ Element.text ("OpenStack Status: " ++ friendlyOpenstackStatus details.openstackStatus)
                        , case server.exoProps.targetOpenstackStatus of
                            Just expectedStatusList ->
                                let
                                    listStr =
                                        expectedStatusList
                                            |> List.map friendlyOpenstackStatus
                                            |> String.join ", "
                                in
                                Element.text ("Transitioning to: " ++ listStr)

                            Nothing ->
                                Element.none
                        , Element.text ("Power State: " ++ friendlyPowerState)
                        , Element.text
                            ("Lock Status: "
                                ++ (case details.lockStatus of
                                        OSTypes.ServerLocked ->
                                            "Locked"

                                        OSTypes.ServerUnlocked ->
                                            "Unlocked"
                                   )
                            )
                        , case VH.getExoSetupStatusStr server of
                            Just setupStatusStr ->
                                Element.text ("Exosphere Setup Status: " ++ setupStatusStr)

                            Nothing ->
                                Element.none
                        ]
            in
            Style.Widgets.ToggleTip.toggleTip context.palette
                contents
                serverDetailViewParams.verboseStatus
                (ProjectMsg projectId <|
                    SetProjectView <|
                        ServerDetail
                            server.osProps.uuid
                            { serverDetailViewParams | verboseStatus = not serverDetailViewParams.verboseStatus }
                )
    in
    Element.row [ Element.spacing 15 ]
        [ statusBadge
        , lockStatus details.lockStatus
        , verboseStatusToggleTip
        ]


interactions : View.Types.Context -> Project -> Server -> Time.Posix -> Maybe UserAppProxyHostname -> ServerDetailViewParams -> Element.Element Msg
interactions context project server currentTime tlsReverseProxyHostname serverDetailViewParams =
    let
        renderInteraction interaction =
            let
                interactionStatus =
                    IHelpers.interactionStatus
                        project
                        server
                        interaction
                        context
                        currentTime
                        tlsReverseProxyHostname

                ( statusWord, statusColor ) =
                    IHelpers.interactionStatusWordColor context.palette interactionStatus

                interactionDetails =
                    IHelpers.interactionDetails interaction context

                interactionToggleTip =
                    let
                        status =
                            Element.row []
                                [ Element.el [ Font.bold ] <| Element.text "Status: "
                                , Element.text statusWord
                                ]

                        statusReason =
                            let
                                renderReason reason =
                                    Element.text <| "(" ++ reason ++ ")"
                            in
                            case interactionStatus of
                                ITypes.Unavailable reason ->
                                    renderReason reason

                                ITypes.Error reason ->
                                    renderReason reason

                                ITypes.Warn _ reason ->
                                    renderReason reason

                                _ ->
                                    Element.none

                        description =
                            Element.paragraph []
                                [ Element.el [ Font.bold ] <| Element.text "Description: "
                                , Element.text interactionDetails.description
                                ]

                        contents =
                            Element.column
                                [ Element.width (Element.shrink |> Element.minimum 200)
                                , Element.spacing 10
                                , Element.padding 5
                                ]
                                [ status
                                , statusReason
                                , description
                                ]

                        shown =
                            case serverDetailViewParams.activeInteractionToggleTip of
                                Just interaction_ ->
                                    interaction == interaction_

                                _ ->
                                    False

                        showHideMsg : ITypes.Interaction -> Msg
                        showHideMsg interaction_ =
                            let
                                newValue =
                                    case serverDetailViewParams.activeInteractionToggleTip of
                                        Just _ ->
                                            Nothing

                                        Nothing ->
                                            Just <| interaction_
                            in
                            ProjectMsg project.auth.project.uuid <|
                                SetProjectView <|
                                    ServerDetail server.osProps.uuid
                                        { serverDetailViewParams | activeInteractionToggleTip = newValue }
                    in
                    Style.Widgets.ToggleTip.toggleTip
                        context.palette
                        contents
                        shown
                        (showHideMsg interaction)
            in
            case interactionStatus of
                ITypes.Hidden ->
                    Element.none

                _ ->
                    Element.row
                        VH.exoRowAttributes
                        [ Icon.roundRect statusColor 14
                        , case interactionDetails.type_ of
                            ITypes.UrlInteraction ->
                                Widget.button
                                    (SH.materialStyle context.palette).button
                                    { text = interactionDetails.name
                                    , icon =
                                        Element.el
                                            [ Element.paddingEach
                                                { top = 0
                                                , right = 5
                                                , left = 0
                                                , bottom = 0
                                                }
                                            ]
                                            (interactionDetails.icon (SH.toElementColor context.palette.primary) 22)
                                    , onPress =
                                        case interactionStatus of
                                            ITypes.Ready url ->
                                                Just <| OpenNewWindow url

                                            ITypes.Warn url _ ->
                                                Just <| OpenNewWindow url

                                            _ ->
                                                Nothing
                                    }

                            ITypes.TextInteraction ->
                                let
                                    ( iconColor, fontColor ) =
                                        case interactionStatus of
                                            ITypes.Ready _ ->
                                                ( SH.toElementColor context.palette.primary
                                                , SH.toElementColor context.palette.on.surface
                                                )

                                            _ ->
                                                ( SH.toElementColor context.palette.muted
                                                , SH.toElementColor context.palette.muted
                                                )
                                in
                                Element.row
                                    [ Font.color fontColor
                                    ]
                                    [ Element.el
                                        [ Font.color iconColor
                                        , Element.paddingEach
                                            { top = 0
                                            , right = 5
                                            , left = 0
                                            , bottom = 0
                                            }
                                        ]
                                        (interactionDetails.icon iconColor 22)
                                    , Element.text interactionDetails.name
                                    , case interactionStatus of
                                        ITypes.Ready text ->
                                            Element.row
                                                []
                                                [ Element.text ": "
                                                , copyableText context.palette [] text
                                                ]

                                        _ ->
                                            Element.none
                                    ]
                        , interactionToggleTip
                        ]
    in
    [ ITypes.GuacTerminal
    , ITypes.GuacDesktop
    , ITypes.NativeSSH
    , ITypes.Console
    ]
        |> List.map renderInteraction
        |> Element.column []


serverPassword : View.Types.Context -> ProjectIdentifier -> ServerDetailViewParams -> Server -> Element.Element Msg
serverPassword context projectId serverDetailViewParams server =
    let
        passwordShower password =
            Element.column
                [ Element.spacing 10 ]
                [ case serverDetailViewParams.passwordVisibility of
                    PasswordShown ->
                        copyableText context.palette [] password

                    PasswordHidden ->
                        Element.none
                , let
                    changeMsg newValue =
                        ProjectMsg projectId <|
                            SetProjectView <|
                                ServerDetail server.osProps.uuid
                                    { serverDetailViewParams | passwordVisibility = newValue }

                    ( buttonText, onPressMsg ) =
                        case serverDetailViewParams.passwordVisibility of
                            PasswordShown ->
                                ( "Hide password"
                                , changeMsg PasswordHidden
                                )

                            PasswordHidden ->
                                ( "Show password"
                                , changeMsg PasswordShown
                                )
                  in
                  Widget.textButton
                    (SH.materialStyle context.palette).button
                    { text = buttonText
                    , onPress = Just onPressMsg
                    }
                ]

        passwordHint =
            GetterSetters.getServerExouserPassword server.osProps.details
                |> Maybe.withDefault (Element.text "Not available yet, check back in a few minutes.")
                << Maybe.map
                    (\password ->
                        Element.column
                            [ Element.spacing 10 ]
                            [ Element.text "Try logging in with username \"exouser\" and the following password:"
                            , passwordShower password
                            ]
                    )
    in
    Element.column
        VH.exoColumnAttributes
        [ passwordHint
        ]


viewServerActions : View.Types.Context -> Project -> ServerDetailViewParams -> Server -> Element.Element Msg
viewServerActions context project serverDetailViewParams server =
    Element.column
        (VH.exoColumnAttributes ++ [ Element.spacingXY 0 10 ])
    <|
        case server.exoProps.targetOpenstackStatus of
            Nothing ->
                List.map
                    (renderServerActionButton context project serverDetailViewParams server)
                    (ServerActions.getAllowed
                        (Just context.localization.virtualComputer)
                        (Just context.localization.staticRepresentationOfBlockDeviceContents)
                        server.osProps.details.openstackStatus
                        server.osProps.details.lockStatus
                    )

            Just _ ->
                []


serverEventHistory :
    View.Types.Context
    -> Time.Posix
    -> RemoteData.WebData (List OSTypes.ServerEvent)
    -> Element.Element Msg
serverEventHistory context currentTime serverEventsWebData =
    case serverEventsWebData of
        RemoteData.Success serverEvents ->
            let
                renderTableHeader : String -> Element.Element Msg
                renderTableHeader headerText =
                    Element.el [ Font.bold ] <| Element.text headerText

                columns : List (Element.Column OSTypes.ServerEvent Msg)
                columns =
                    [ { header = renderTableHeader "Action"
                      , width = Element.px 180
                      , view =
                            \event ->
                                let
                                    actionStr =
                                        event.action
                                            |> String.replace "_" " "
                                in
                                Element.paragraph [] [ Element.text actionStr ]
                      }
                    , { header = renderTableHeader "Time"
                      , width = Element.px 180
                      , view =
                            \event ->
                                let
                                    relativeTime =
                                        DateFormat.Relative.relativeTime currentTime event.startTime
                                in
                                Element.text <|
                                    relativeTime
                      }
                    , { header = Element.none
                      , width = Element.px 200
                      , view =
                            \event ->
                                let
                                    absoluteTime =
                                        Helpers.Time.humanReadableTime event.startTime
                                in
                                Element.text <|
                                    "("
                                        ++ absoluteTime
                                        ++ ")"
                      }
                    ]
            in
            Element.column [ Element.paddingXY 0 10, Element.spacing 10, Element.width Element.fill ]
                [ Element.el VH.heading4 <| Element.text "Action History"
                , Element.table
                    (VH.formContainer
                        ++ [ Element.spacingXY 0 7
                           , Border.widthEach { top = 1, bottom = 1, left = 0, right = 0 }
                           , Border.color (context.palette.muted |> SH.toElementColor)
                           ]
                    )
                    { data = serverEvents, columns = columns }
                ]

        _ ->
            Element.none


renderServerActionButton : View.Types.Context -> Project -> ServerDetailViewParams -> Server -> ServerActions.ServerAction -> Element.Element Msg
renderServerActionButton context project serverDetailViewParams server serverAction =
    let
        displayConfirmation =
            case serverDetailViewParams.serverActionNamePendingConfirmation of
                Nothing ->
                    False

                Just actionName ->
                    actionName == serverAction.name
    in
    case ( serverAction.action, serverAction.confirmable, displayConfirmation ) of
        ( ServerActions.CmdAction _, True, False ) ->
            let
                updateAction =
                    ProjectMsg
                        project.auth.project.uuid
                        (SetProjectView
                            (ServerDetail
                                server.osProps.uuid
                                { serverDetailViewParams | serverActionNamePendingConfirmation = Just serverAction.name }
                            )
                        )
            in
            renderActionButton context serverAction (Just updateAction) serverAction.name

        ( ServerActions.CmdAction cmdAction, True, True ) ->
            let
                renderKeepFloatingIpCheckbox : List (Element.Element Msg)
                renderKeepFloatingIpCheckbox =
                    if
                        serverAction.name
                            == "Delete"
                            && (not <| List.isEmpty <| GetterSetters.getServerFloatingIps project server.osProps.uuid)
                    then
                        [ Input.checkbox
                            []
                            { onChange =
                                \new ->
                                    ProjectMsg
                                        project.auth.project.uuid
                                        (SetProjectView
                                            (ServerDetail
                                                server.osProps.uuid
                                                { serverDetailViewParams | retainFloatingIpsWhenDeleting = new }
                                            )
                                        )
                            , icon = Input.defaultCheckbox
                            , checked = serverDetailViewParams.retainFloatingIpsWhenDeleting
                            , label =
                                Input.labelRight []
                                    (Element.text <|
                                        String.join " "
                                            [ "Keep the"
                                            , context.localization.floatingIpAddress
                                            , "of this"
                                            , context.localization.virtualComputer
                                            , "for future use"
                                            ]
                                    )
                            }
                        ]

                    else
                        []

                actionMsg =
                    if serverAction.name == "Delete" then
                        -- Override action so that we can pass through user's choice of whether to retain floating IPs
                        Just <|
                            ProjectMsg project.auth.project.uuid <|
                                ServerMsg server.osProps.uuid <|
                                    RequestDeleteServer serverDetailViewParams.retainFloatingIpsWhenDeleting

                    else
                        Just <|
                            ProjectMsg project.auth.project.uuid <|
                                ServerMsg server.osProps.uuid <|
                                    RequestServerAction
                                        cmdAction
                                        serverAction.targetStatus

                cancelMsg =
                    Just <|
                        ProjectMsg
                            project.auth.project.uuid
                            (SetProjectView
                                (ServerDetail
                                    server.osProps.uuid
                                    { serverDetailViewParams | serverActionNamePendingConfirmation = Nothing }
                                )
                            )

                title =
                    confirmationMessage serverAction
            in
            Element.column
                [ Element.spacing 5 ]
            <|
                List.concat
                    [ [ renderConfirmationButton context serverAction actionMsg cancelMsg title ]
                    , renderKeepFloatingIpCheckbox
                    ]

        ( ServerActions.CmdAction cmdAction, False, _ ) ->
            let
                actionMsg =
                    Just <|
                        ProjectMsg project.auth.project.uuid <|
                            ServerMsg server.osProps.uuid <|
                                RequestServerAction
                                    cmdAction
                                    serverAction.targetStatus

                title =
                    serverAction.name
            in
            renderActionButton context serverAction actionMsg title

        ( ServerActions.UpdateAction updateAction, _, _ ) ->
            let
                actionMsg =
                    Just <| updateAction project.auth.project.uuid server

                title =
                    serverAction.name
            in
            renderActionButton context serverAction actionMsg title


confirmationMessage : ServerActions.ServerAction -> String
confirmationMessage serverAction =
    "Are you sure you want to " ++ (serverAction.name |> String.toLower) ++ "?"


serverActionSelectModButton : View.Types.Context -> ServerActions.SelectMod -> (Widget.TextButton Msg -> Element.Element Msg)
serverActionSelectModButton context selectMod =
    case selectMod of
        ServerActions.NoMod ->
            Widget.textButton (SH.materialStyle context.palette).button

        ServerActions.Primary ->
            Widget.textButton (SH.materialStyle context.palette).primaryButton

        ServerActions.Warning ->
            Widget.textButton (SH.materialStyle context.palette).warningButton

        ServerActions.Danger ->
            Widget.textButton (SH.materialStyle context.palette).dangerButton


renderActionButton : View.Types.Context -> ServerActions.ServerAction -> Maybe Msg -> String -> Element.Element Msg
renderActionButton context serverAction actionMsg title =
    Element.row
        [ Element.spacing 10 ]
        [ Element.el
            [ Element.width <| Element.px 120 ]
          <|
            serverActionSelectModButton context
                serverAction.selectMod
                { text = title
                , onPress = actionMsg
                }
        , Element.text serverAction.description

        -- TODO hover text with description
        ]


renderConfirmationButton : View.Types.Context -> ServerActions.ServerAction -> Maybe Msg -> Maybe Msg -> String -> Element.Element Msg
renderConfirmationButton context serverAction actionMsg cancelMsg title =
    Element.row
        [ Element.spacing 10 ]
        [ Element.text title
        , Element.el
            []
          <|
            serverActionSelectModButton context
                serverAction.selectMod
                { text = "Yes"
                , onPress = actionMsg
                }
        , Element.el
            []
          <|
            Widget.textButton (SH.materialStyle context.palette).button
                { text = "No"
                , onPress = cancelMsg
                }

        -- TODO hover text with description
        ]


resourceUsageCharts : View.Types.Context -> Int -> ( Time.Posix, Time.Zone ) -> Server -> Element.Element Msg
resourceUsageCharts context chartsWidthPx currentTimeAndZone server =
    let
        thirtyMinMillis =
            1000 * 60 * 30
    in
    case server.exoProps.serverOrigin of
        ServerNotFromExo ->
            Element.text <|
                String.join " "
                    [ "Charts not available because"
                    , context.localization.virtualComputer
                    , "was not created by Exosphere."
                    ]

        ServerFromExo exoOriginProps ->
            case exoOriginProps.resourceUsage.data of
                RDPP.DoHave history _ ->
                    if Dict.isEmpty history.timeSeries then
                        if Helpers.serverLessThanThisOld server (Tuple.first currentTimeAndZone) thirtyMinMillis then
                            Element.text <|
                                String.join " "
                                    [ "No chart data yet. This"
                                    , context.localization.virtualComputer
                                    , "is new and may take a few minutes to start reporting data."
                                    ]

                        else
                            Element.text "No chart data to show."

                    else
                        Element.column [ Element.width Element.fill ]
                            [ View.ResourceUsage.alerts context (Tuple.first currentTimeAndZone) history.timeSeries
                            , View.ResourceUsage.charts context chartsWidthPx currentTimeAndZone history.timeSeries
                            ]

                _ ->
                    if exoOriginProps.exoServerVersion < 2 then
                        Element.text <|
                            String.join " "
                                [ "Charts not available because"
                                , context.localization.virtualComputer
                                , "was not created using a new enough build of Exosphere."
                                ]

                    else
                        Element.text <|
                            String.join " "
                                [ "Could not access the"
                                , context.localization.virtualComputer
                                , "console log, charts not available."
                                ]


renderIpAddresses : View.Types.Context -> Project -> Server -> ServerDetailViewParams -> Element.Element Msg
renderIpAddresses context project server serverDetailViewParams =
    let
        fixedIpAddressRows =
            GetterSetters.getServerFixedIps project server.osProps.uuid
                |> List.map
                    (\ipAddress ->
                        VH.compactKVSubRow
                            (Helpers.String.toTitleCase context.localization.nonFloatingIpAddress)
                            (Element.text ipAddress)
                    )

        floatingIpAddressRows =
            if List.isEmpty (GetterSetters.getServerFloatingIps project server.osProps.uuid) then
                if server.exoProps.floatingIpCreationOption == DoNotUseFloatingIp then
                    -- The server doesn't have a floating IP and we aren't waiting to create one, so give user option to assign one
                    [ Element.text <|
                        String.join " "
                            [ "No"
                            , context.localization.floatingIpAddress
                            , "assigned."
                            ]
                    , Widget.textButton
                        (SH.materialStyle context.palette).button
                        { text =
                            String.join " "
                                [ "Assign a", context.localization.floatingIpAddress ]
                        , onPress =
                            Just <|
                                ProjectMsg project.auth.project.uuid <|
                                    SetProjectView <|
                                        AssignFloatingIp (AssignFloatingIpViewParams Nothing (Just server.osProps.uuid))
                        }
                    ]

                else
                    -- Floating IP is not yet created as part of server launch, but it might be.
                    [ Element.text <|
                        String.join " "
                            [ "No"
                            , context.localization.floatingIpAddress
                            , "yet, please wait"
                            ]
                    ]

            else
                GetterSetters.getServerFloatingIps project server.osProps.uuid
                    |> List.map
                        (\ipAddress ->
                            VH.compactKVSubRow
                                (Helpers.String.toTitleCase context.localization.floatingIpAddress)
                                (Element.column VH.exoColumnAttributes
                                    [ copyableText context.palette [] ipAddress.address
                                    , Widget.textButton
                                        (SH.materialStyle context.palette).button
                                        { text =
                                            "Unassign"
                                        , onPress =
                                            Just <| ProjectMsg project.auth.project.uuid <| RequestUnassignFloatingIp ipAddress.uuid
                                        }
                                    ]
                                )
                        )

        ipButton : Element.Element Msg -> String -> IPInfoLevel -> Element.Element Msg
        ipButton label displayLabel ipMsg =
            Element.row
                [ Element.spacing 3 ]
                [ Input.button
                    [ Font.size 10
                    , Border.width 1
                    , Border.rounded 20
                    , Border.color (SH.toElementColor context.palette.muted)
                    , Element.padding 3
                    ]
                    { onPress =
                        Just <|
                            ProjectMsg project.auth.project.uuid <|
                                SetProjectView <|
                                    ServerDetail
                                        server.osProps.uuid
                                        { serverDetailViewParams | ipInfoLevel = ipMsg }
                    , label = label
                    }
                , Element.el [ Font.size 10 ] (Element.text displayLabel)
                ]
    in
    case serverDetailViewParams.ipInfoLevel of
        IPDetails ->
            let
                icon =
                    FeatherIcons.chevronDown
                        |> FeatherIcons.withSize 12
                        |> FeatherIcons.toHtml []
                        |> Element.html
            in
            Element.column
                (VH.exoColumnAttributes ++ [ Element.padding 0 ])
                (floatingIpAddressRows
                    ++ ipButton icon "IP Details" IPSummary
                    :: fixedIpAddressRows
                )

        IPSummary ->
            let
                icon =
                    FeatherIcons.chevronRight
                        |> FeatherIcons.withSize 12
                        |> FeatherIcons.toHtml []
                        |> Element.html
            in
            Element.column
                (VH.exoColumnAttributes ++ [ Element.padding 0 ])
                (floatingIpAddressRows ++ [ ipButton icon "IP Details" IPDetails ])


serverVolumes : View.Types.Context -> Project -> Server -> Element.Element Msg
serverVolumes context project server =
    let
        vols =
            GetterSetters.getVolsAttachedToServer project server

        deviceRawName vol =
            vol.attachments
                |> List.filter (\a -> a.serverUuid == server.osProps.uuid)
                |> List.head
                |> Maybe.map .device

        isBootVol vol =
            deviceRawName vol
                |> Maybe.map (\d -> List.member d [ "/dev/vda", "/dev/sda" ])
                |> Maybe.withDefault False
    in
    case List.length vols of
        0 ->
            Element.text "(none)"

        _ ->
            let
                volDetailsButton v =
                    Style.Widgets.IconButton.goToButton context.palette
                        (Just
                            (ProjectMsg
                                project.auth.project.uuid
                                (SetProjectView <| VolumeDetail v.uuid [])
                            )
                        )

                volumeRow v =
                    let
                        ( device, mountpoint ) =
                            if isBootVol v then
                                ( String.join " "
                                    [ "Boot"
                                    , context.localization.blockDevice
                                    ]
                                , ""
                                )

                            else
                                case deviceRawName v of
                                    Just device_ ->
                                        ( device_
                                        , case Helpers.volDeviceToMountpoint device_ of
                                            Just mountpoint_ ->
                                                mountpoint_

                                            Nothing ->
                                                "Could not determine"
                                        )

                                    Nothing ->
                                        ( "Could not determine", "" )
                    in
                    { name = VH.possiblyUntitledResource v.name "volume"
                    , device = device
                    , mountpoint = mountpoint
                    , toButton = volDetailsButton v
                    }
            in
            Element.table
                []
                { data =
                    vols
                        |> List.map volumeRow
                        |> List.sortBy .device
                , columns =
                    [ { header = Element.el [ Font.heavy ] <| Element.text "Name"
                      , width = Element.fill
                      , view = \v -> Element.text v.name
                      }
                    , { header = Element.el [ Font.heavy ] <| Element.text "Device"
                      , width = Element.fill
                      , view = \v -> Element.text v.device
                      }
                    , { header = Element.el [ Font.heavy ] <| Element.text "Mount point *"
                      , width = Element.fill
                      , view = \v -> Element.text v.mountpoint
                      }
                    , { header = Element.none
                      , width = Element.px 22
                      , view = \v -> v.toButton
                      }
                    ]
                }
