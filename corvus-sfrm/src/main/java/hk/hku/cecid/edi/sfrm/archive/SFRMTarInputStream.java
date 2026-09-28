package hk.hku.cecid.edi.sfrm.archive;

import java.io.InputStream;

import org.apache.tools.tar.TarInputStream;

public class SFRMTarInputStream extends TarInputStream {

    public SFRMTarInputStream(InputStream input) {
        super(input, SFRMTarUtils.NAME_ENCODING);
    }

    public SFRMTarInputStream(InputStream input, int blockSize) {
        super(input, blockSize, SFRMTarUtils.NAME_ENCODING);
    }

    public SFRMTarInputStream(InputStream input, int blockSize, int recordSize) {
        super(input, blockSize, recordSize, SFRMTarUtils.NAME_ENCODING);
    }
}
