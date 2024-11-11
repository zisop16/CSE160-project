configuration LinkStateC {
    provides interface LinkState;
}

implementation {
    components LinkStateP;
    components NeighborDiscoveryC;
    components FloodingC;
    components SocketC;

    components new SimpleSendC(AM_PACK);
    components new TimerMilliC() as sendTimer;

    LinkStateP.sendTimer -> sendTimer;
    LinkStateP.Sender -> SimpleSendC;

    
    LinkState = LinkStateP.LinkState;
    LinkStateP.NeighborDiscovery -> NeighborDiscoveryC;
    LinkStateP.Socket -> SocketC;
    LinkStateP.Flooding -> FloodingC;
}