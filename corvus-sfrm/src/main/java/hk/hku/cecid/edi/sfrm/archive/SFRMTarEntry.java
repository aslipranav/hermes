package hk.hku.cecid.edi.sfrm.archive;

import java.io.File;

import org.apache.tools.tar.TarEntry;

public class SFRMTarEntry extends TarEntry {

    public SFRMTarEntry(String name) {
        super(name);
    }

    public SFRMTarEntry(String name, byte linkFlag) {
        super(name, linkFlag);
    }

    public SFRMTarEntry(File file) {
        super(file);
    }

    public SFRMTarEntry(byte[] headerBuffer) {
        super(headerBuffer);
    }
}
