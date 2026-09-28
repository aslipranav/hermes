package hk.hku.cecid.edi.sfrm.archive;

import java.nio.charset.StandardCharsets;

public final class SFRMTarUtils {

    public static final String NAME_ENCODING = "UTF-8";

    /**
     * Retains the public legacy constructor for source and binary callers.
     */
    public SFRMTarUtils() {
    }

    public static StringBuffer parseName(byte[] header, int offset, int length) {
        int nameLength = length;
        int end = offset + length;

        for (int i = offset; i < end; i++) {
            if (header[i] == 0) {
                nameLength = i - offset;
                break;
            }
        }

        return new StringBuffer(new String(header, offset, nameLength, StandardCharsets.UTF_8));
    }

    public static int getNameBytes(StringBuffer name, byte[] buffer, int offset, int length) {
        byte[] nameBytes = name.toString().getBytes(StandardCharsets.UTF_8);
        int nameLength = Math.min(nameBytes.length, length);
        System.arraycopy(nameBytes, 0, buffer, offset, nameLength);
        for (; nameLength < length; nameLength++) {
            buffer[offset + nameLength] = 0;
        }
        return offset + length;
    }
}
