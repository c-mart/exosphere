module View exposing (view)

import Base64
import Element
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Element.Region as Region
import Filesize exposing (format)
import Helpers
import Html exposing (Html)
import Maybe
import RemoteData
import Types.Types exposing (..)


view : Model -> Html Msg
view model =
    Element.layout
        []
        (elementView model)


elementView : Model -> Element.Element Msg
elementView model =
    Element.column
        [ Element.padding 10
        ]
        [ viewProviderPicker model
        , case model.viewState of
            NonProviderView viewConstructor ->
                case viewConstructor of
                    Login ->
                        viewLogin model

            ProviderView providerName viewConstructor ->
                case Helpers.providerLookup model providerName of
                    Nothing ->
                        Element.text "Oops! Provider not found"

                    Just provider ->
                        providerView model provider viewConstructor
        , viewMessages model
        ]


providerView : Model -> Provider -> ProviderViewConstructor -> Element.Element Msg
providerView model provider viewConstructor =
    case viewConstructor of
        ListImages ->
            Element.column []
                [ viewNav provider
                , viewImagesIfLoaded model.globalDefaults provider model.imageFilterTag
                ]

        ListProviderServers ->
            Element.column []
                [ viewNav provider
                , viewServers provider
                ]

        ServerDetail serverUuid ->
            Element.column []
                [ viewNav provider
                , viewServerDetail provider serverUuid
                ]

        CreateServer createServerRequest ->
            Element.column []
                [ viewNav provider
                , viewCreateServer provider createServerRequest
                ]



{- Sub-views for most/all pages -}


viewMessages : Model -> Element.Element Msg
viewMessages model =
    Element.column [] (List.map renderMessage model.messages)


viewProviderPicker : Model -> Element.Element Msg
viewProviderPicker model =
    Element.column []
        [ Element.el [ Region.heading 2 ] (Element.text "Providers")
        , Element.column []
            [ Element.column [] (List.map (renderProviderPicker model) model.providers)
            ]
        , uiButton { label = Element.text "Add Provider", onPress = Just (SetNonProviderView Login) }
        ]


viewNav : Provider -> Element.Element Msg
viewNav provider =
    Element.column []
        [ Element.el [ Region.heading 2 ] (Element.text "Navigation")
        , uiButton { label = Element.text "My Servers", onPress = Just (ProviderMsg provider.name (SetProviderView ListProviderServers)) }
        , uiButton { label = Element.text "Create Server", onPress = Just (ProviderMsg provider.name (SetProviderView ListImages)) }
        ]



{- Resource-specific views -}


viewLogin : Model -> Element.Element Msg
viewLogin model =
    Element.column
        [ Element.spacing 20
        ]
        [ Element.el
            [ Region.heading 2
            , Font.size 24
            , Font.bold
            ]
            (Element.text "Please log in")
        , Element.wrappedRow
            [ Element.spacing 10 ]
            [ viewLoginCredsEntry model
            , viewLoginOpenRcEntry model
            ]
        , Element.el [ Element.alignRight ] (uiButton { label = Element.text "Log in", onPress = Just RequestNewProviderToken })
        ]


viewLoginCredsEntry : Model -> Element.Element Msg
viewLoginCredsEntry model =
    Element.column
        [ Element.width (Element.px 800)
        , Element.height Element.shrink
        , Element.alignTop
        , Element.centerX
        , Element.spacing 10
        , Element.padding 10
        ]
        [ Element.el [] (Element.text "Either enter your credentials...")
        , Input.text
            [ Element.spacing 12
            ]
            { text = model.creds.authUrl
            , placeholder = Just (Input.placeholder [] (Element.text "Auth URL e.g. https://mycloud.net:5000/v3"))
            , onChange = \u -> InputLoginField (AuthUrl u)
            , label = Input.labelAbove [ Font.size 14 ] (Element.text "Keystone auth URL")
            }
        , Input.text
            [ Element.spacing 12
            ]
            { text = model.creds.projectDomain
            , placeholder = Just (Input.placeholder [] (Element.text "Project domain e.g. default"))
            , onChange = \d -> InputLoginField (ProjectDomain d)
            , label = Input.labelAbove [ Font.size 14 ] (Element.text "Project Domain")
            }
        , Input.text
            [ Element.spacing 12
            ]
            { text = model.creds.projectName
            , placeholder = Just (Input.placeholder [] (Element.text "Project name e.g. demo"))
            , onChange = \pn -> InputLoginField (ProjectName pn)
            , label = Input.labelAbove [ Font.size 14 ] (Element.text "Project Name")
            }
        , Input.text
            [ Element.spacing 12
            ]
            { text = model.creds.userDomain
            , placeholder = Just (Input.placeholder [] (Element.text "User domain e.g. default"))
            , onChange = \d -> InputLoginField (UserDomain d)
            , label = Input.labelAbove [ Font.size 14 ] (Element.text "User Domain")
            }
        , Input.text
            [ Element.spacing 12
            ]
            { text = model.creds.username
            , placeholder = Just (Input.placeholder [] (Element.text "User name e.g. demo"))
            , onChange = \u -> InputLoginField (Username u)
            , label = Input.labelAbove [ Font.size 14 ] (Element.text "User Name")
            }
        , Input.currentPassword
            [ Element.spacing 12
            ]
            { text = model.creds.password
            , placeholder = Just (Input.placeholder [] (Element.text "Password"))
            , show = False
            , onChange = \p -> InputLoginField (Password p)
            , label = Input.labelAbove [ Font.size 14 ] (Element.text "Password")
            }
        ]


viewLoginOpenRcEntry : Model -> Element.Element Msg
viewLoginOpenRcEntry model =
    Element.column
        [ Element.height Element.fill
        , Element.spacing 15
        ]
        [ Element.paragraph []
            [ Element.text "...or paste an "

            {-
               Todo this link opens in Electron, should open in user's browser
               https://github.com/electron/electron/blob/master/docs/api/shell.md#shellopenexternalurl-options-callback
            -}
            , Element.link []
                { url = "https://docs.openstack.org/newton/install-guide-rdo/keystone-openrc.html"
                , label = Element.text "OpenRC"
                }
            , Element.text " file"
            ]
        , Input.multiline
            [ Element.width (Element.px 300)
            , Element.height (Element.px 200)
            , Font.size 12
            ]
            { onChange = \o -> InputLoginField (OpenRc o)
            , text = "export..."
            , placeholder = Nothing
            , label = Input.labelLeft [] Element.none
            , spellcheck = False
            }
        ]


viewImagesIfLoaded : GlobalDefaults -> Provider -> Maybe String -> Element.Element Msg
viewImagesIfLoaded globalDefaults provider maybeFilterTag =
    case List.isEmpty provider.images of
        True ->
            Element.column [] [ Element.row [] [ Element.text "Images loading" ] ]

        False ->
            viewImages globalDefaults provider maybeFilterTag


viewImages : GlobalDefaults -> Provider -> Maybe String -> Element.Element Msg
viewImages globalDefaults provider maybeFilterTag =
    let
        imageContainsTag tag image =
            List.member tag image.tags

        filteredImages =
            case maybeFilterTag of
                Nothing ->
                    provider.images

                Just filterTag ->
                    List.filter (imageContainsTag filterTag) provider.images

        noMatchWarning =
            (maybeFilterTag /= Nothing) && (List.length filteredImages == 0)

        displayedImages =
            if noMatchWarning == False then
                filteredImages

            else
                provider.images
    in
    Element.column
        [ Element.spacing 10
        ]
        [ Element.el [ Region.heading 2 ] (Element.text "Choose an image")
        , Input.text []
            { text = Maybe.withDefault "" maybeFilterTag
            , placeholder = Just (Input.placeholder [] (Element.text "try \"distro-base\""))
            , onChange = \t -> InputImageFilterTag t
            , label = Input.labelAbove [ Font.size 14 ] (Element.text "Filter on tag:")
            }
        , uiButton { label = Element.text "Clear filter (show all)", onPress = Just (InputImageFilterTag "") }
        , if noMatchWarning then
            Element.text "No matches found, showing all images"

          else
            Element.none
        , Element.wrappedRow
            [ Element.spacing 20
            ]
            (List.map (renderImage globalDefaults provider) displayedImages)
        ]


viewServers : Provider -> Element.Element Msg
viewServers provider =
    case provider.servers of
        RemoteData.NotAsked ->
            Element.paragraph [] [ Element.text "Please wait..." ]

        RemoteData.Loading ->
            Element.paragraph [] [ Element.text "Loading..." ]

        RemoteData.Failure e ->
            Element.paragraph [] [ Element.text ("Cannot display servers. Error message: " ++ Debug.toString e) ]

        RemoteData.Success servers ->
            case List.isEmpty servers of
                True ->
                    Element.paragraph [] [ Element.text "You don't have any servers yet, go create one!" ]

                False ->
                    let
                        noServersSelected =
                            List.any .selected servers |> not

                        allServersSelected =
                            List.all .selected servers

                        selectedServers =
                            List.filter .selected servers

                        deleteButtonOnPress =
                            if noServersSelected == True then
                                Nothing

                            else
                                Just (ProviderMsg provider.name (RequestDeleteServers selectedServers))
                    in
                    Element.column []
                        [ Element.el [ Region.heading 2 ] (Element.text "My Servers")
                        , Element.column [ Element.padding 5, Element.spacing 10, Border.width 1 ]
                            [ Element.text "Bulk Actions"
                            , Input.checkbox []
                                { checked = allServersSelected
                                , onChange = \new -> ProviderMsg provider.name (SelectAllServers new)
                                , icon = Input.defaultCheckbox
                                , label = Input.labelRight [] (Element.text "Select All")
                                }
                            , uiButton { label = Element.text "Delete", onPress = deleteButtonOnPress }
                            ]
                        , Element.column [] (List.map (renderServer provider) servers)
                        ]


viewServerDetail : Provider -> ServerUuid -> Element.Element Msg
viewServerDetail provider serverUuid =
    let
        maybeServer =
            Helpers.serverLookup provider serverUuid
    in
    case maybeServer of
        Nothing ->
            Element.text "No server found"

        Just server ->
            case server.details of
                Nothing ->
                    Element.text "Retrieving details??"

                Just details ->
                    let
                        maybeFlavor =
                            Helpers.flavorLookup provider details.flavorUuid

                        flavorText =
                            case maybeFlavor of
                                Just flavor ->
                                    flavor.name

                                Nothing ->
                                    "Unknown flavor"

                        maybeImage =
                            Helpers.imageLookup provider details.imageUuid

                        imageText =
                            case maybeImage of
                                Just image ->
                                    image.name

                                Nothing ->
                                    "Unknown image"

                        maybeFloatingIp =
                            Helpers.getFloatingIp details.ipAddresses

                        interactionLinks cockpitStatus =
                            case maybeFloatingIp of
                                Just floatingIp ->
                                    let
                                        interactionLinksBase =
                                            [ Element.row []
                                                [ uiButton
                                                    { label = Element.text "Launch Terminal"
                                                    , onPress = Just (OpenInBrowser ("https://" ++ floatingIp ++ ":9090/cockpit/@localhost/system/terminal.html"))
                                                    }
                                                , Element.text "Type commands in a shell!"
                                                ]
                                            , Element.row
                                                []
                                                [ uiButton
                                                    { label = Element.text "Launch Cockpit"
                                                    , onPress = Just (OpenInBrowser ("https://" ++ floatingIp ++ ":9090"))
                                                    }
                                                , Element.text "Manage your server with an interactive dashboard!"
                                                ]
                                            , Element.text "- These links will open in a new browser window; you may need to accept a self-signed certificate warning"
                                            , Element.text "- Then, log in with your previously chosen username and password"
                                            ]
                                    in
                                    case cockpitStatus of
                                        NotChecked ->
                                            Element.text "Status of terminal and cockpit not available yet."

                                        CheckedNotReady ->
                                            Element.text "Terminal and Cockpit not ready yet."

                                        Ready ->
                                            Element.column []
                                                ([ Element.text "Terminal and Cockpit are ready..." ]
                                                    ++ interactionLinksBase
                                                )

                                        Error ->
                                            Element.column []
                                                ([ Element.text "Unable to detect status of Terminal and Cockpit services. These links may work a few minutes after your server is active." ]
                                                    ++ interactionLinksBase
                                                )

                                Nothing ->
                                    Element.text "Terminal and Cockpit services not ready yet."
                    in
                    Element.column []
                        [ Element.el [ Region.heading 2 ] (Element.text "Server Details")
                        , Element.row []
                            [ Element.text "Name: "
                            , Element.text server.name
                            ]
                        , Element.row []
                            [ Element.text "UUID: "
                            , Element.text server.uuid
                            ]
                        , Element.row []
                            [ Element.text "Created on: "
                            , Element.text details.created
                            ]
                        , Element.row []
                            [ Element.text "Status: "
                            , Element.text details.status
                            ]
                        , Element.row []
                            [ Element.text "Power state: "
                            , Element.text (Debug.toString details.powerState)
                            ]
                        , Element.row []
                            [ Element.text "Image: "
                            , Element.text imageText
                            ]
                        , Element.row []
                            [ Element.text "Flavor: "
                            , Element.text flavorText
                            ]
                        , Element.row []
                            [ Element.text "SSH Key Name: "
                            , Element.text details.keypairName
                            ]
                        , Element.row []
                            [ Element.text "IP addresses: "
                            , renderIpAddresses details.ipAddresses
                            ]
                        , Element.el [ Region.heading 2 ] (Element.text "Interact with server")
                        , interactionLinks server.cockpitStatus
                        ]


viewCreateServer : Provider -> CreateServerRequest -> Element.Element Msg
viewCreateServer provider createServerRequest =
    Element.row []
        [ Element.column [ Element.spacing 10, Element.padding 10, Element.width (Element.px 600) ]
            [ Element.el [ Region.heading 2 ] (Element.text "Create Server")
            , Input.text
                [ Element.spacing 12
                ]
                { text = createServerRequest.name
                , placeholder = Just (Input.placeholder [] (Element.text "My Server"))
                , onChange = \n -> InputCreateServerField createServerRequest (CreateServerName n)
                , label = Input.labelLeft [] (Element.text "Name")
                }
            , Element.row [] [ Element.text "Image: ", Element.text createServerRequest.imageName ]
            , Element.row [ Element.spacing 10 ]
                [ Element.el [ Element.width Element.shrink ] (Element.text createServerRequest.count)
                , Input.slider
                    [ Element.height (Element.px 30)
                    , Element.width (Element.px 100 |> Element.minimum 200)

                    -- Here is where we're creating/styling the "track"
                    , Element.behindContent
                        (Element.el
                            [ Element.width Element.fill
                            , Element.height (Element.px 2)
                            , Element.centerY
                            , Background.color (Element.rgb 0.5 0.5 0.5)
                            , Border.rounded 2
                            ]
                            Element.none
                        )
                    ]
                    { onChange = \c -> InputCreateServerField createServerRequest (CreateServerCount (String.fromFloat c))
                    , label = Input.labelLeft [] (Element.text "How many?")
                    , min = 1
                    , max = 10
                    , step = Just 1
                    , value = String.toFloat createServerRequest.count |> Maybe.withDefault 1.0
                    , thumb =
                        Input.defaultThumb
                    }
                ]
            , viewFlavorPicker provider createServerRequest
            , viewVolBackedPrompt provider createServerRequest
            , viewKeypairPicker provider createServerRequest
            , viewUserDataInput provider createServerRequest
            , uiButton
                { onPress = Just (ProviderMsg provider.name (RequestCreateServer createServerRequest))
                , label = Element.text "Create"
                }
            ]
        ]



{- View Helpers -}


renderMessage : String -> Element.Element Msg
renderMessage message =
    Element.paragraph [] [ Element.text message ]


renderProviderPicker : Model -> Provider -> Element.Element Msg
renderProviderPicker model provider =
    let
        isSelected p =
            case model.viewState of
                NonProviderView _ ->
                    False

                ProviderView selectedProvName _ ->
                    p.name == selectedProvName
    in
    case isSelected provider of
        False ->
            uiButton { label = Element.text provider.name, onPress = Just (ProviderMsg provider.name (SetProviderView ListProviderServers)) }

        True ->
            Element.text provider.name


renderImage : GlobalDefaults -> Provider -> Image -> Element.Element Msg
renderImage globalDefaults provider image =
    let
        size =
            case image.size of
                Just s ->
                    format s

                Nothing ->
                    "N/A"

        checksum =
            case image.checksum of
                Just c ->
                    c

                Nothing ->
                    "N/A"
    in
    Element.column
        [ Element.spacing 10
        , Element.height Element.fill
        , Element.width (Element.px 500)
        , Border.width 1
        , Border.shadow
            { offset = ( 2, 2 )
            , size = 2
            , blur = 1
            , color = Element.rgba 0.3 0.3 0.3 0.6
            }
        , Element.padding 10
        ]
        [ Element.paragraph [ Font.heavy ] [ Element.text image.name ]
        , Element.el [] (uiButton { label = Element.text "Launch", onPress = Just (ProviderMsg provider.name (SetProviderView (CreateServer (CreateServerRequest "" provider.name image.uuid image.name "1" "" False "" "" globalDefaults.shellUserData)))) })
        , Element.row []
            [ Element.text "Status: "
            , Element.text (Debug.toString image.status)
            ]
        , Element.row []
            [ Element.text "Size: "
            , Element.text size
            ]
        , Element.row []
            [ Element.text "Tags: "
            , Element.text (List.foldl (\a b -> a ++ ", " ++ b) "" image.tags)
            ]
        ]


renderServer : Provider -> Server -> Element.Element Msg
renderServer provider server =
    Element.column []
        [ Input.checkbox []
            { checked = server.selected
            , onChange = \new -> ProviderMsg provider.name (SelectServer server new)
            , icon = Input.defaultCheckbox
            , label = Input.labelRight [] (Element.el [ Font.bold ] (Element.text server.name))
            }
        , Element.row [ Element.spacing 10 ]
            [ Element.text ("UUID: " ++ server.uuid)
            , uiButton { label = Element.text "Details", onPress = Just (ProviderMsg provider.name (SetProviderView (ServerDetail server.uuid))) }
            , if server.deletionAttempted == True then
                Element.text "Deleting..."

              else
                uiButton { label = Element.text "Delete", onPress = Just (ProviderMsg provider.name (RequestDeleteServer server)) }
            ]
        ]


getEffectiveUserDataSize : CreateServerRequest -> String
getEffectiveUserDataSize createServerRequest =
    let
        rawLength =
            String.length createServerRequest.userData

        base64Value =
            Base64.encode createServerRequest.userData

        base64Length =
            String.length base64Value
    in
    String.fromInt rawLength
        ++ " characters,  "
        ++ String.fromInt base64Length
        ++ "/16384 allowed bytes (Base64 encoded)"


renderIpAddresses : List IpAddress -> Element.Element Msg
renderIpAddresses ipAddresses =
    Element.column [] (List.map renderIpAddress ipAddresses)


renderIpAddress : IpAddress -> Element.Element Msg
renderIpAddress ipAddress =
    Element.paragraph []
        [ Element.text (Debug.toString ipAddress.openstackType ++ ": " ++ ipAddress.address)
        ]


viewFlavorPicker : Provider -> CreateServerRequest -> Element.Element Msg
viewFlavorPicker provider createServerRequest =
    let
        sortedFlavors flavors =
            flavors
                |> List.sortBy .disk_ephemeral
                |> List.sortBy .disk_root
                |> List.sortBy .ram_mb
                |> List.sortBy .vcpu

        flavorAsStr flavor =
            flavor.name ++ " (" ++ String.fromInt flavor.vcpu ++ " CPU, " ++ (flavor.ram_mb // 1024 |> String.fromInt) ++ " GB RAM, " ++ String.fromInt flavor.disk_root ++ " GB root disk, " ++ String.fromInt flavor.disk_ephemeral ++ " GB ephemeral disk)"

        flavorAsOption flavor =
            Input.option flavor.uuid (Element.text (flavorAsStr flavor))
    in
    Input.radio []
        { label = Input.labelAbove [ Element.paddingXY 0 12 ] (Element.text "Size")
        , onChange = \new -> InputCreateServerField createServerRequest (CreateServerSize new)
        , options = List.map flavorAsOption (sortedFlavors provider.flavors)
        , selected = Just createServerRequest.flavorUuid
        }


viewVolBackedPrompt : Provider -> CreateServerRequest -> Element.Element Msg
viewVolBackedPrompt provider createServerRequest =
    let
        maybeFlavor =
            List.filter (\f -> f.uuid == createServerRequest.flavorUuid) provider.flavors
                |> List.head

        flavorRootDiskSize =
            case maybeFlavor of
                Nothing ->
                    {- This should be an impossible state -}
                    0

                Just flavor ->
                    flavor.disk_root

        nonVolBackedOptionText =
            if flavorRootDiskSize == 0 then
                "Default for selected image (warning, could be too small for your work)"

            else
                String.fromInt flavorRootDiskSize ++ " GB (default for selected size)"
    in
    Input.radio []
        { label = Input.labelAbove [ Element.paddingXY 0 12 ] (Element.text "Choose a root disk size")
        , onChange = \new -> InputCreateServerField createServerRequest (CreateServerVolBacked new)
        , options =
            [ Input.option False (Element.text nonVolBackedOptionText)
            , Input.option True
                (Element.row
                    [ Element.spacing 10 ]
                    [ --                    Element.el [ Element.width Element.shrink ] (Element.text createServerRequest.volBackedSizeGb)
                      Input.slider
                        [ Element.height (Element.px 30)
                        , Element.width (Element.px 100 |> Element.minimum 200)

                        -- Here is where we're creating/styling the "track"
                        , Element.behindContent
                            (Element.el
                                [ Element.width Element.fill
                                , Element.height (Element.px 2)
                                , Element.centerY
                                , Background.color (Element.rgb 0.5 0.5 0.5)
                                , Border.rounded 2
                                ]
                                Element.none
                            )
                        ]
                        { onChange = \c -> InputCreateServerField createServerRequest (CreateServerVolBackedSize (String.fromFloat c))
                        , label = Input.labelRight [] (Element.text (createServerRequest.volBackedSizeGb ++ " GB (will use a volume for root disk)"))
                        , min = 2
                        , max = 20
                        , step = Just 1
                        , value = String.toFloat createServerRequest.volBackedSizeGb |> Maybe.withDefault 2.0
                        , thumb =
                            Input.defaultThumb
                        }
                    ]
                )
            ]
        , selected = Just createServerRequest.volBacked
        }


viewKeypairPicker : Provider -> CreateServerRequest -> Element.Element Msg
viewKeypairPicker provider createServerRequest =
    let
        keypairAsOption keypair =
            Input.option keypair.name (Element.text keypair.name)
    in
    Input.radio []
        { label = Input.labelAbove [ Element.paddingXY 0 12 ] (Element.text "SSH Keypair")
        , onChange = \keypairName -> InputCreateServerField createServerRequest (CreateServerKeypairName keypairName)
        , options = List.map keypairAsOption provider.keypairs
        , selected = Just createServerRequest.keypairName
        }


viewUserDataInput : Provider -> CreateServerRequest -> Element.Element Msg
viewUserDataInput provider createServerRequest =
    Input.multiline
        [ Element.width (Element.px 300)
        , Element.height (Element.px 200)
        ]
        { onChange = \u -> InputCreateServerField createServerRequest (CreateServerUserData u)
        , text = createServerRequest.userData
        , placeholder = Just (Input.placeholder [] (Element.text "#!/bin/bash\n\n# Your script here"))
        , label = Input.labelAbove [] (Element.text "User Data (Boot Script)")
        , spellcheck = False
        }



{- Elm UI Doodads -}


uiButton : { onPress : Maybe Msg, label : Element.Element Msg } -> Element.Element Msg
uiButton props =
    let
        borderColor =
            if props.onPress == Nothing then
                -- This should be where we decide what a disabled button looks like
                Element.rgb 0.8 0.8 0.8

            else
                Element.rgb 0 0 0
    in
    Input.button
        [ Element.padding 5
        , Border.rounded 6
        , Border.color borderColor
        , Border.width 1
        ]
        props
