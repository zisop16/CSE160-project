configuration LinkStateC {
    provides interface LinkState;
}

implementation {
    components LinkStateP;

    LinkState = LinkStateP.LinkState;
}