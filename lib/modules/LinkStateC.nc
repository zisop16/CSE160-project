configuration LinkStateC {
    provides interface LinkState;
}

implementation {
    components LinkStateP;
    components NeighborDiscoveryC;
    components FloodingC;

    components new SimpleSendC(AM_PACK);
    components new TimerMilliC() as sendTimer;

    LinkStateP.sendTimer -> sendTimer;
    LinkStateP.Sender -> SimpleSendC;

    
    LinkState = LinkStateP.LinkState;
    LinkStateP.NeighborDiscovery -> NeighborDiscoveryC;
    LinkStateP.Flooding -> FloodingC;
}