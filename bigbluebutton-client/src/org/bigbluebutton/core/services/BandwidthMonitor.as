package org.bigbluebutton.core.services
{
  import flash.events.AsyncErrorEvent;
  import flash.events.IOErrorEvent;
  import flash.events.NetStatusEvent;
  import flash.events.TimerEvent;
  import flash.net.NetConnection;
  import flash.utils.Timer;
  
  import mx.utils.ObjectUtil;

  import org.bigbluebutton.common.LogUtil;
  import org.bigbluebutton.main.model.NetworkStatsData;

  import org.red5.flash.bwcheck.ClientServerBandwidth;
  import org.red5.flash.bwcheck.ServerClientBandwidth;
  import org.red5.flash.bwcheck.events.BandwidthDetectEvent;

  public class BandwidthMonitor {
  	public static const INTERVAL_BETWEEN_CHECKS:int = 30000; // in ms
  
	private static var _instance:BandwidthMonitor = null;
    private var _serverURL:String = "localhost";
    private var _serverApplication:String = "video";
    private var _clientServerService:String = "checkBandwidthUp";
    private var _serverClientService:String = "checkBandwidth";
    private var _pendingClientToServer:Boolean;
    private var _pendingServerToClient:Boolean;
    private var _lastClientToServerCheck:Date;
    private var _lastServerToClientCheck:Date;
    private var _runningMeasurement:Boolean;
    private var _connecting:Boolean;
    private var _nc:NetConnection;
    
	/**
	 * This class is a singleton. Please initialize it using the getInstance() method.
	 */		
	public function BandwidthMonitor(enforcer:SingletonEnforcer) {
		if (enforcer == null) {
			throw new Error("There can only be one instance of this class");
		}
		initialize();
	}
	
	private function initialize():void {
		_pendingClientToServer = false;
		_pendingServerToClient = false;
	    _runningMeasurement = false;
	    _connecting = false;
	    _lastClientToServerCheck = null;
	    _lastServerToClientCheck = null;
		
		_nc = new NetConnection();
		_nc.objectEncoding = flash.net.ObjectEncoding.AMF0;
		_nc.client = this;
		_nc.addEventListener(NetStatusEvent.NET_STATUS, onStatus);
		_nc.addEventListener(AsyncErrorEvent.ASYNC_ERROR, onAsyncError);
		_nc.addEventListener(IOErrorEvent.IO_ERROR, onIOError);
	}
	
	/**
	 * Return the single instance of this class
	 */
	public static function getInstance():BandwidthMonitor {
		if (_instance == null) {
			_instance = new BandwidthMonitor(new SingletonEnforcer());
		}
		return _instance;
	}    
    
    public function set serverURL(url:String):void {
    	if (_nc.connected)
			_nc.close();
		_serverURL = url;
    }
    
    public function set serverApplication(app:String):void {
    	if (_nc.connected)
			_nc.close();
		_serverApplication = app;
    }

    private function connect():void {
    	if (!_nc.connected && !_connecting) {
			_nc.connect("rtmp://" + _serverURL + "/" + _serverApplication);
			_connecting = true;
		}
    }
    
    public function checkClientToServer():void {
    	if (_lastClientToServerCheck != null && _lastClientToServerCheck.getTime() + INTERVAL_BETWEEN_CHECKS > new Date().getTime())
    		return;
    	
    	if (!_nc.connected) {
    		_pendingClientToServer = true;
    		connect();
		} if (_runningMeasurement) {
    		_pendingClientToServer = true;
		} else {
    		_pendingClientToServer = false;
    		_runningMeasurement = true;
    		_lastClientToServerCheck = new Date();

			LogUtil.debug("Start client-server bandwidth detection");
			var clientServer:ClientServerBandwidth  = new ClientServerBandwidth();
			clientServer.connection = _nc;
			clientServer.service = _clientServerService;
			clientServer.addEventListener(BandwidthDetectEvent.DETECT_COMPLETE,onClientServerComplete);
			clientServer.addEventListener(BandwidthDetectEvent.DETECT_STATUS,onClientServerStatus);
			clientServer.addEventListener(BandwidthDetectEvent.DETECT_FAILED,onDetectFailed);
			clientServer.start();
		}
    }
    
    public function checkServerToClient():void {
    	if (_lastServerToClientCheck != null && _lastServerToClientCheck.getTime() + INTERVAL_BETWEEN_CHECKS > new Date().getTime())
    		return;

    	if (!_nc.connected) {
    		_pendingServerToClient = true;
    		connect();
		} if (_runningMeasurement) {
    		_pendingServerToClient = true;
		} else {
    		_pendingServerToClient = false;
    		_runningMeasurement = true;
    		_lastServerToClientCheck = new Date();

			LogUtil.debug("Start server-client bandwidth detection");
			var serverClient:ServerClientBandwidth = new ServerClientBandwidth();
			serverClient.connection = _nc;
			serverClient.service = _serverClientService;
			serverClient.addEventListener(BandwidthDetectEvent.DETECT_COMPLETE,onServerClientComplete);
			serverClient.addEventListener(BandwidthDetectEvent.DETECT_STATUS,onServerClientStatus);
			serverClient.addEventListener(BandwidthDetectEvent.DETECT_FAILED,onDetectFailed);
			serverClient.start();
		}
    }
    
    private function checkPendingOperations():void {
      if (_pendingClientToServer) checkClientToServer();
      if (_pendingServerToClient) checkServerToClient();
    }
    
    private function onAsyncError(event:AsyncErrorEvent):void {
		LogUtil.debug(event.error.toString());
    }

    private function onIOError(event:IOErrorEvent):void {
		LogUtil.debug(event.text);
    }
    
    private function onStatus(event:NetStatusEvent):void
    {
      switch (event.info.code)
      {
        case "NetConnection.Connect.Success":
          LogUtil.debug("Connection established to measure bandwidth");
          break;
        default:
          LogUtil.debug("Cannot establish the connection to measure bandwidth");
          break;
      }
      _connecting = false;
      checkPendingOperations();
    }
    
    public function onDetectFailed(event:BandwidthDetectEvent):void {
      LogUtil.debug("Detection failed with error: " + event.info.application + " " + event.info.description);
      _runningMeasurement = false;
    }
    
    public function onClientServerComplete(event:BandwidthDetectEvent):void {
      LogUtil.debug("Client-server bandwidth detection complete");
//      LogUtil.debug(ObjectUtil.toString(event.info));
      NetworkStatsData.getInstance().setUploadMeasuredBW(event.info);
      _runningMeasurement = false;
      checkPendingOperations();
    }
    
    public function onClientServerStatus(event:BandwidthDetectEvent):void {
//      if (event.info) {
//        LogUtil.debug("\n count: "+event.info.count+ " sent: "+event.info.sent+" timePassed: "+event.info.timePassed+" latency: "+event.info.latency+" overhead:  "+event.info.overhead+" packet interval: " + event.info.pakInterval + " cumLatency: " + event.info.cumLatency);
//      }
    }
    
    public function onServerClientComplete(event:BandwidthDetectEvent):void {
      LogUtil.debug("Server-client bandwidth detection complete");
//      LogUtil.debug(ObjectUtil.toString(event.info));
      NetworkStatsData.getInstance().setDownloadMeasuredBW(event.info);
      _runningMeasurement = false;
      checkPendingOperations();
    }
    
    public function onServerClientStatus(event:BandwidthDetectEvent):void {	
//      if (event.info) {
//        LogUtil.debug("\n count: "+event.info.count+ " sent: "+event.info.sent+" timePassed: "+event.info.timePassed+" latency: "+event.info.latency+" cumLatency: " + event.info.cumLatency);
//      }
    }
  }
}

class SingletonEnforcer{}