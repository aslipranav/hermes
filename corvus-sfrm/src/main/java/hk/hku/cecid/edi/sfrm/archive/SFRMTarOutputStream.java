package hk.hku.cecid.edi.sfrm.archive;

import java.io.OutputStream;

import org.apache.tools.tar.TarOutputStream;

public class SFRMTarOutputStream extends TarOutputStream {

    public SFRMTarOutputStream(OutputStream output) {
        super(output, SFRMTarUtils.NAME_ENCODING);
    }

    public SFRMTarOutputStream(OutputStream output, int blockSize) {
        super(output, blockSize, SFRMTarUtils.NAME_ENCODING);
    }

    public SFRMTarOutputStream(OutputStream output, int blockSize, int recordSize) {
        super(output, blockSize, recordSize, SFRMTarUtils.NAME_ENCODING);
    }
}
