module Types.Types exposing
    ( AllResourcesListViewParams
    , AssignFloatingIpViewParams
    , CloudSpecificConfig
    , CreateServerViewParams
    , DeleteConfirmation
    , DeleteVolumeConfirmation
    , Endpoints
    , ExcludeFilter
    , ExoServerProps
    , ExoServerVersion
    , ExoSetupStatus(..)
    , Flags
    , FloatingIpListViewParams
    , FloatingIpState(..)
    , HttpRequestMethod(..)
    , IPInfoLevel(..)
    , ImageListViewParams
    , JetstreamCreds
    , JetstreamProvider(..)
    , KeypairIdentifier
    , KeypairListViewParams
    , KeystoneHostname
    , Localization
    , LogMessage
    , LoginView(..)
    , Model
    , Msg(..)
    , NewServerNetworkOptions(..)
    , NonProjectViewConstructor(..)
    , OpenIdConnectLoginConfig
    , PasswordVisibility(..)
    , Project
    , ProjectIdentifier
    , ProjectName
    , ProjectSecret(..)
    , ProjectSpecificMsgConstructor(..)
    , ProjectTitle
    , ProjectViewConstructor(..)
    , ProjectViewParams
    , ResourceUsageRDPP
    , Server
    , ServerDetailActiveTooltip(..)
    , ServerDetailViewParams
    , ServerFromExoProps
    , ServerListViewParams
    , ServerOrigin(..)
    , ServerSelection
    , ServerSpecificMsgConstructor(..)
    , ServerUiStatus(..)
    , SortTableParams
    , Style
    , SupportableItemType(..)
    , TickInterval
    , Toast
    , UnscopedProvider
    , UnscopedProviderProject
    , UserAppProxyHostname
    , VerboseStatus
    , ViewState(..)
    , VolumeListViewParams
    , WindowSize
    , currentExoServerVersion
    )

import Browser.Navigation
import Color
import Dict
import Helpers.RemoteDataPlusPlus as RDPP
import Http
import Json.Decode as Decode
import OpenStack.Types as OSTypes
import RemoteData exposing (WebData)
import Set
import Style.Types
import Style.Widgets.NumericTextInput.Types exposing (NumericTextInput(..))
import Time
import Toasty
import Types.Error exposing (ErrorContext, HttpErrorWithBody)
import Types.Guacamole as GuacTypes
import Types.HelperTypes as HelperTypes
import Types.Interaction exposing (Interaction)
import Types.ServerResourceUsage
import UUID
import Url



{- App-Level Types -}


type alias Flags =
    -- Flags intended to be configured by cloud operators
    { showDebugMsgs : Bool
    , cloudCorsProxyUrl : Maybe HelperTypes.Url
    , urlPathPrefix : Maybe String
    , appTitle : Maybe String
    , palette :
        Maybe
            { primary :
                { r : Int
                , g : Int
                , b : Int
                }
            , secondary :
                { r : Int
                , g : Int
                , b : Int
                }
            }
    , logo : Maybe String
    , favicon : Maybe String
    , defaultLoginView : Maybe String
    , aboutAppMarkdown : Maybe String
    , supportInfoMarkdown : Maybe String
    , userSupportEmail : Maybe String
    , openIdConnectLoginConfig :
        Maybe OpenIdConnectLoginConfig
    , localization : Maybe Localization
    , clouds :
        List
            { keystoneHostname : KeystoneHostname
            , userAppProxy : Maybe UserAppProxyHostname
            , imageExcludeFilter : Maybe ExcludeFilter
            , featuredImageNamePrefix : Maybe String
            }
    , instanceConfigMgtRepoUrl : Maybe String
    , instanceConfigMgtRepoCheckout : Maybe String

    -- Flags that Exosphere sets dynamically
    , width : Int
    , height : Int
    , storedState : Maybe Decode.Value
    , randomSeed0 : Int
    , randomSeed1 : Int
    , randomSeed2 : Int
    , randomSeed3 : Int
    , epoch : Int
    , timeZone : Int
    }


type alias CloudSpecificConfig =
    { userAppProxy : Maybe UserAppProxyHostname
    , imageExcludeFilter : Maybe ExcludeFilter
    , featuredImageNamePrefix : Maybe String
    }


type alias WindowSize =
    { width : Int
    , height : Int
    }


type alias Model =
    { logMessages : List LogMessage
    , urlPathPrefix : Maybe String
    , navigationKey : Browser.Navigation.Key

    -- Used to determine whether to pushUrl (change of view) or replaceUrl (just change of view parameters)
    , prevUrl : String
    , viewState : ViewState
    , maybeWindowSize : Maybe WindowSize
    , unscopedProviders : List UnscopedProvider
    , projects : List Project
    , toasties : Toasty.Stack Toast
    , cloudCorsProxyUrl : Maybe CloudCorsProxyUrl
    , clientUuid : UUID.UUID
    , clientCurrentTime : Time.Posix
    , timeZone : Time.Zone
    , showDebugMsgs : Bool
    , style : Style
    , openIdConnectLoginConfig :
        Maybe OpenIdConnectLoginConfig
    , cloudSpecificConfigs : Dict.Dict KeystoneHostname CloudSpecificConfig
    , instanceConfigMgtRepoUrl : HelperTypes.Url
    , instanceConfigMgtRepoCheckout : String
    }


type alias ExcludeFilter =
    { filterKey : String
    , filterValue : String
    }


type alias Localization =
    { openstackWithOwnKeystone : String
    , openstackSharingKeystoneWithAnother : String
    , unitOfTenancy : String
    , maxResourcesPerProject : String
    , pkiPublicKeyForSsh : String
    , virtualComputer : String
    , virtualComputerHardwareConfig : String
    , cloudInitData : String
    , commandDrivenTextInterface : String
    , staticRepresentationOfBlockDeviceContents : String
    , blockDevice : String
    , nonFloatingIpAddress : String
    , floatingIpAddress : String
    , graphicalDesktopEnvironment : String
    }


type alias Style =
    { logo : HelperTypes.Url
    , primaryColor : Color.Color
    , secondaryColor : Color.Color
    , styleMode : Style.Types.StyleMode
    , appTitle : String
    , defaultLoginView : Maybe LoginView
    , aboutAppMarkdown : Maybe String
    , supportInfoMarkdown : Maybe String
    , userSupportEmail : String
    , localization : Localization
    }


type alias OpenIdConnectLoginConfig =
    { keystoneAuthUrl : String
    , webssoKeystoneEndpoint : String
    , oidcLoginIcon : String
    , oidcLoginButtonLabel : String
    , oidcLoginButtonDescription : String
    }


type alias CloudCorsProxyUrl =
    HelperTypes.Url


type alias KeystoneHostname =
    HelperTypes.Hostname


type alias UserAppProxyHostname =
    HelperTypes.Hostname


type alias LogMessage =
    { message : String
    , context : ErrorContext
    , timestamp : Time.Posix
    }


type alias UnscopedProvider =
    { authUrl : OSTypes.KeystoneUrl
    , token : OSTypes.UnscopedAuthToken
    , projectsAvailable : WebData (List UnscopedProviderProject)
    }


type alias UnscopedProviderProject =
    { project : OSTypes.NameAndUuid
    , description : String
    , domainId : HelperTypes.Uuid
    , enabled : Bool
    }


type alias Project =
    { secret : ProjectSecret
    , auth : OSTypes.ScopedAuthToken
    , endpoints : Endpoints
    , images : List OSTypes.Image
    , servers : RDPP.RemoteDataPlusPlus HttpErrorWithBody (List Server)
    , flavors : List OSTypes.Flavor
    , keypairs : WebData (List OSTypes.Keypair)
    , volumes : WebData (List OSTypes.Volume)
    , networks : RDPP.RemoteDataPlusPlus HttpErrorWithBody (List OSTypes.Network)
    , autoAllocatedNetworkUuid : RDPP.RemoteDataPlusPlus HttpErrorWithBody OSTypes.NetworkUuid
    , floatingIps : WebData (List OSTypes.FloatingIp)
    , ports : RDPP.RemoteDataPlusPlus HttpErrorWithBody (List OSTypes.Port)
    , securityGroups : List OSTypes.SecurityGroup
    , computeQuota : WebData OSTypes.ComputeQuota
    , volumeQuota : WebData OSTypes.VolumeQuota
    , pendingCredentialedRequests : List (OSTypes.AuthTokenString -> Cmd Msg) -- Requests waiting for a valid auth token
    }


type alias ProjectIdentifier =
    -- We use this when referencing a Project in a Msg (or otherwise passing through the runtime)
    HelperTypes.Uuid


type ProjectSecret
    = OpenstackPassword HelperTypes.Password
    | ApplicationCredential OSTypes.ApplicationCredential
    | NoProjectSecret


type alias Endpoints =
    { cinder : HelperTypes.Url
    , glance : HelperTypes.Url
    , keystone : HelperTypes.Url
    , nova : HelperTypes.Url
    , neutron : HelperTypes.Url
    }


type Msg
    = Tick TickInterval Time.Posix
    | DoOrchestration Time.Posix
    | SetNonProjectView NonProjectViewConstructor
    | HandleApiErrorWithBody ErrorContext HttpErrorWithBody
    | RequestUnscopedToken OSTypes.OpenstackLogin
    | RequestNewProjectToken OSTypes.OpenstackLogin
    | JetstreamLogin JetstreamCreds
    | ReceiveScopedAuthToken ( Http.Metadata, String )
    | ReceiveUnscopedAuthToken OSTypes.KeystoneUrl ( Http.Metadata, String )
    | ReceiveUnscopedProjects OSTypes.KeystoneUrl (List UnscopedProviderProject)
    | RequestProjectLoginFromProvider OSTypes.KeystoneUrl (List UnscopedProviderProject)
    | ProjectMsg ProjectIdentifier ProjectSpecificMsgConstructor
    | InputOpenRc OSTypes.OpenstackLogin String
    | OpenNewWindow String
    | NavigateToUrl String
    | ToastyMsg (Toasty.Msg Toast)
    | MsgChangeWindowSize Int Int
    | UrlChange Url.Url
    | SetStyle Style.Types.StyleMode
    | NoOp


type alias TickInterval =
    Int


type ProjectSpecificMsgConstructor
    = SetProjectView ProjectViewConstructor
    | ReceiveAppCredential OSTypes.ApplicationCredential
    | PrepareCredentialedRequest (Maybe HelperTypes.Url -> OSTypes.AuthTokenString -> Cmd Msg) Time.Posix
    | ToggleCreatePopup
    | RemoveProject
    | ServerMsg OSTypes.ServerUuid ServerSpecificMsgConstructor
    | RequestServers
    | RequestCreateServer CreateServerViewParams OSTypes.NetworkUuid
    | RequestDeleteServers (List OSTypes.ServerUuid)
    | RequestCreateVolume OSTypes.VolumeName OSTypes.VolumeSize
    | RequestDeleteVolume OSTypes.VolumeUuid
    | RequestDetachVolume OSTypes.VolumeUuid
    | RequestKeypairs
    | RequestCreateKeypair OSTypes.KeypairName OSTypes.PublicKey
    | RequestDeleteKeypair OSTypes.KeypairName
    | RequestDeleteFloatingIp OSTypes.IpAddressUuid
    | RequestAssignFloatingIp OSTypes.Port OSTypes.IpAddressUuid
    | RequestUnassignFloatingIp OSTypes.IpAddressUuid
    | ReceiveImages (List OSTypes.Image)
    | ReceiveServer OSTypes.ServerUuid ErrorContext (Result HttpErrorWithBody OSTypes.Server)
    | ReceiveServers ErrorContext (Result HttpErrorWithBody (List OSTypes.Server))
    | ReceiveCreateServer OSTypes.ServerUuid
    | ReceiveFlavors (List OSTypes.Flavor)
    | ReceiveKeypairs (List OSTypes.Keypair)
    | ReceiveCreateKeypair OSTypes.Keypair
    | ReceiveDeleteKeypair ErrorContext OSTypes.KeypairName (Result Http.Error ())
    | ReceiveNetworks ErrorContext (Result HttpErrorWithBody (List OSTypes.Network))
    | ReceiveAutoAllocatedNetwork ErrorContext (Result HttpErrorWithBody OSTypes.NetworkUuid)
    | ReceiveFloatingIps (List OSTypes.FloatingIp)
    | ReceivePorts ErrorContext (Result HttpErrorWithBody (List OSTypes.Port))
    | ReceiveDeleteFloatingIp OSTypes.IpAddressUuid
    | ReceiveAssignFloatingIp OSTypes.FloatingIp
    | ReceiveUnassignFloatingIp OSTypes.FloatingIp
    | ReceiveSecurityGroups (List OSTypes.SecurityGroup)
    | ReceiveCreateExoSecurityGroup OSTypes.SecurityGroup
    | ReceiveCreateVolume
    | ReceiveVolumes (List OSTypes.Volume)
    | ReceiveDeleteVolume
    | ReceiveUpdateVolumeName
    | ReceiveAttachVolume OSTypes.VolumeAttachment
    | ReceiveDetachVolume
    | ReceiveComputeQuota OSTypes.ComputeQuota
    | ReceiveVolumeQuota OSTypes.VolumeQuota


type ServerSpecificMsgConstructor
    = RequestServer
    | RequestDeleteServer
    | RequestSetServerName String
    | RequestAttachVolume OSTypes.VolumeUuid
    | RequestCreateServerImage String
    | ReceiveServerEvents ErrorContext (Result HttpErrorWithBody (List OSTypes.ServerEvent))
    | ReceiveConsoleUrl (Result HttpErrorWithBody OSTypes.ConsoleUrl)
    | ReceiveDeleteServer (Maybe OSTypes.IpAddressValue)
    | ReceiveCreateFloatingIp ErrorContext (Result HttpErrorWithBody OSTypes.FloatingIp)
    | ReceiveServerPassword OSTypes.ServerPassword
    | ReceiveSetServerName String ErrorContext (Result HttpErrorWithBody String)
    | ReceiveSetServerMetadata OSTypes.MetadataItem ErrorContext (Result HttpErrorWithBody (List OSTypes.MetadataItem))
    | ReceiveGuacamoleAuthToken (Result Http.Error GuacTypes.GuacamoleAuthToken)
    | RequestServerAction (Project -> Server -> Cmd Msg) (Maybe (List OSTypes.ServerStatus))
    | ReceiveConsoleLog ErrorContext (Result HttpErrorWithBody String)


type ViewState
    = NonProjectView NonProjectViewConstructor
    | ProjectView ProjectIdentifier ProjectViewParams ProjectViewConstructor


type NonProjectViewConstructor
    = LoginPicker
    | Login LoginView
    | LoadingUnscopedProjects OSTypes.AuthTokenString
    | SelectProjects OSTypes.KeystoneUrl (List UnscopedProviderProject)
    | MessageLog Bool
    | Settings
    | GetSupport (Maybe ( SupportableItemType, Maybe HelperTypes.Uuid )) String Bool
    | HelpAbout
    | PageNotFound


type
    SupportableItemType
    -- Ideally this would be in View.Types, eh
    = SupportableProject
    | SupportableImage
    | SupportableServer
    | SupportableVolume


type LoginView
    = LoginOpenstack OSTypes.OpenstackLogin
    | LoginJetstream JetstreamCreds


type alias ImageListViewParams =
    { searchText : String
    , tags : Set.Set String
    , onlyOwnImages : Bool
    , expandImageDetails : Set.Set OSTypes.ImageUuid
    }


type alias SortTableParams =
    { title : String
    , asc : Bool
    }


type alias ProjectViewParams =
    { createPopup : Bool
    }


type ProjectViewConstructor
    = AllResources AllResourcesListViewParams
    | ListImages ImageListViewParams SortTableParams
    | ListProjectServers ServerListViewParams
    | ListProjectVolumes VolumeListViewParams
    | ListFloatingIps FloatingIpListViewParams
    | AssignFloatingIp AssignFloatingIpViewParams
    | ListKeypairs KeypairListViewParams
    | CreateKeypair String String
    | ServerDetail OSTypes.ServerUuid ServerDetailViewParams
    | CreateServerImage OSTypes.ServerUuid String
    | VolumeDetail OSTypes.VolumeUuid (List DeleteVolumeConfirmation)
    | CreateServer CreateServerViewParams
    | CreateVolume OSTypes.VolumeName NumericTextInput
    | AttachVolumeModal (Maybe OSTypes.ServerUuid) (Maybe OSTypes.VolumeUuid)
    | MountVolInstructions OSTypes.VolumeAttachment


type alias AllResourcesListViewParams =
    { serverListViewParams : ServerListViewParams
    , volumeListViewParams : VolumeListViewParams
    , keypairListViewParams : KeypairListViewParams
    , floatingIpListViewParams : FloatingIpListViewParams
    }


type alias ServerListViewParams =
    { onlyOwnServers : Bool
    , selectedServers : Set.Set ServerSelection
    , deleteConfirmations : List DeleteConfirmation
    }


type alias ServerDetailViewParams =
    { verboseStatus : VerboseStatus
    , passwordVisibility : PasswordVisibility
    , ipInfoLevel : IPInfoLevel
    , serverActionNamePendingConfirmation : Maybe String
    , serverNamePendingConfirmation : Maybe String
    , activeTooltip : Maybe ServerDetailActiveTooltip
    }


type ServerDetailActiveTooltip
    = InteractionTooltip Interaction
    | InteractionStatusTooltip Interaction


type alias VolumeListViewParams =
    { expandedVols : List OSTypes.VolumeUuid
    , deleteConfirmations : List DeleteVolumeConfirmation
    }


type alias CreateServerViewParams =
    { serverName : String
    , imageUuid : OSTypes.ImageUuid
    , imageName : String
    , count : Int
    , flavorUuid : OSTypes.FlavorUuid
    , volSizeTextInput : Maybe NumericTextInput
    , userDataTemplate : String
    , networkUuid : Maybe OSTypes.NetworkUuid
    , showAdvancedOptions : Bool
    , keypairName : Maybe String
    , deployGuacamole : Maybe Bool -- Nothing when cloud doesn't support Guacamole
    , deployDesktopEnvironment : Bool
    , installOperatingSystemUpdates : Bool
    }


type alias ServerSelection =
    OSTypes.ServerUuid


type alias DeleteConfirmation =
    OSTypes.ServerUuid


type alias DeleteVolumeConfirmation =
    OSTypes.VolumeUuid


type alias FloatingIpListViewParams =
    { deleteConfirmations : List OSTypes.IpAddressUuid
    , hideAssignedIps : Bool
    }


type alias AssignFloatingIpViewParams =
    { ipUuid : Maybe OSTypes.IpAddressUuid
    , serverUuid : Maybe OSTypes.ServerUuid
    }


type alias KeypairListViewParams =
    { expandedKeypairs : List KeypairIdentifier
    , deleteConfirmations : List KeypairIdentifier
    }


type alias KeypairIdentifier =
    ( OSTypes.KeypairName, OSTypes.KeypairFingerprint )


type IPInfoLevel
    = IPDetails
    | IPSummary


type alias VerboseStatus =
    Bool


type PasswordVisibility
    = PasswordShown
    | PasswordHidden


type alias JetstreamCreds =
    { jetstreamProviderChoice : JetstreamProvider
    , jetstreamProjectName : String
    , taccUsername : String
    , taccPassword : String
    }


type JetstreamProvider
    = IUCloud
    | TACCCloud
    | BothJetstreamClouds



-- Resource-Level Types


type alias Server =
    { osProps : OSTypes.Server
    , exoProps : ExoServerProps
    , events : WebData (List OSTypes.ServerEvent)
    }


type alias ExoServerProps =
    { priorFloatingIpState : FloatingIpState
    , deletionAttempted : Bool
    , targetOpenstackStatus : Maybe (List OSTypes.ServerStatus) -- Maybe we have performed an instance action and are waiting for server to reflect that
    , serverOrigin : ServerOrigin
    , receivedTime : Maybe Time.Posix -- Used only if this server was polled more recently than the other servers in the project
    , loadingSeparately : Bool -- Again, used only if server was polled more recently on its own.
    }


type ServerOrigin
    = ServerFromExo ServerFromExoProps
    | ServerNotFromExo


type alias ServerFromExoProps =
    { exoServerVersion : ExoServerVersion
    , exoSetupStatus : RDPP.RemoteDataPlusPlus HttpErrorWithBody ExoSetupStatus
    , resourceUsage : ResourceUsageRDPP
    , guacamoleStatus : GuacTypes.ServerGuacamoleStatus
    , exoCreatorUsername : Maybe String
    }


type alias ResourceUsageRDPP =
    RDPP.RemoteDataPlusPlus HttpErrorWithBody Types.ServerResourceUsage.History


type alias ExoServerVersion =
    Int


currentExoServerVersion : ExoServerVersion
currentExoServerVersion =
    4


type FloatingIpState
    = Unknown
    | NotRequestable
    | Requestable
    | RequestedWaiting
    | Success
    | Failed


type ServerUiStatus
    = ServerUiStatusUnknown
    | ServerUiStatusBuilding
    | ServerUiStatusPartiallyActive
    | ServerUiStatusReady
    | ServerUiStatusPaused
    | ServerUiStatusReboot
    | ServerUiStatusSuspended
    | ServerUiStatusShutoff
    | ServerUiStatusStopped
    | ServerUiStatusSoftDeleted
    | ServerUiStatusError
    | ServerUiStatusRescued
    | ServerUiStatusShelved
    | ServerUiStatusDeleted


type ExoSetupStatus
    = ExoSetupWaiting
    | ExoSetupRunning
    | ExoSetupComplete
    | ExoSetupError
    | ExoSetupTimeout
    | ExoSetupUnknown


type alias ProjectName =
    String


type alias ProjectTitle =
    String


type NewServerNetworkOptions
    = NetworksLoading
    | AutoSelectedNetwork OSTypes.NetworkUuid
    | ManualNetworkSelection
    | NoneAvailable



-- REST Types


type HttpRequestMethod
    = Get
    | Post
    | Put
    | Delete


type alias Toast =
    { context : ErrorContext
    , error : String
    }
