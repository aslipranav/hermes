package hk.hku.cecid.edi.sfrm.archive;

import java.io.File;
import java.io.FileOutputStream;

import hk.hku.cecid.piazza.commons.os.OSCommander;
import hk.hku.cecid.piazza.commons.test.utils.FixtureStore;
import junit.framework.Assert;
import junit.framework.TestCase;
import org.apache.tools.tar.TarEntry;

/**
 * @author Patrick Yip
 *
 */
public class ArchiverTarTest extends TestCase {
	private ClassLoader FIXTURE_LOADER = FixtureStore.createFixtureLoader(false, this.getClass());
	public void setUp(){
		System.out.println("Starting " + this.getName());
	}
	
	public void tearDown(){
		System.out.println("Shutdown " + this.getName());
	}
	
	/**
	 * Test for untar the file
	 * Notice: Run this test should have at least 4GB disk space
	 * @throws Exception
	 */
	public void testExtractFile() throws Exception{
		OSCommander os = new OSCommander();
		
		//10MB
		long payloadSize = 10485760L;		
		
		String payloadName = "10MB";
		
		File dummyFile = new File(FIXTURE_LOADER.getResource("Src").getFile(), payloadName) ;
		File tarFile = new File(FIXTURE_LOADER.getResource("Compressed").getFile(), payloadName + ".tar");
		File extractDir = new File(FIXTURE_LOADER.getResource("Extracted").getFile());
		File extractedFile = null;
		
		try{
			os.createDummyFile(dummyFile.getAbsolutePath(), payloadSize);
			Assert.assertTrue("dummyFile didn't created", dummyFile.exists());
			ArchiverTar tar = new ArchiverTar();
			//Compress the file firstly
			tar.compress(dummyFile, tarFile, true);
			dummyFile.delete();
			//Extract the file
			tar.extract(tarFile, extractDir);
			extractedFile = new File(extractDir, payloadName);
			//Check that whether the extracted file size is the same as orginial 
			Assert.assertEquals("Extracted payload size should be " + Long.toString(payloadSize), payloadSize, extractedFile.length());
			Assert.assertEquals("Extracted file name should same as original", dummyFile.getName(), extractedFile.getName());
		}catch(Exception e){
			e.printStackTrace();
			throw e;
		}finally{
			if(tarFile.exists())
				tarFile.delete();
			if(extractedFile.exists())
				extractedFile.delete();
		}
	}
	
	
	/**
	 * Test for tar the file with long filename, for traditional tar format
	 * , it only support the tar entry name <= 100 characters
	 * @throws Exception
	 */
	public void testCompressLongFileName() throws Exception{
		OSCommander os = new OSCommander();
		
		long payloadSize = 10485760L;
		String payloadName = "01234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789";
		
		File dummyFile = new File(FIXTURE_LOADER.getResource("Src").getFile(), payloadName);
		File tarFile = new File(FIXTURE_LOADER.getResource("Compressed").getFile(), payloadName + ".tar");
		File extractDir = new File(FIXTURE_LOADER.getResource("Extracted").getFile());
		File extractedFile = null;
		
		try{
			os.createDummyFile(dummyFile.getAbsolutePath(), payloadSize);
			Assert.assertTrue("dummyFile didn't created", dummyFile.exists());
			ArchiverTar tar = new ArchiverTar();
			//Compress the file firstly
			tar.compress(dummyFile, tarFile, true);
			dummyFile.delete();
			//Extract the file
			tar.extract(tarFile, extractDir);
			extractedFile = new File(extractDir, payloadName);
			Assert.assertTrue("Untar file should exist", extractedFile.exists());
			//Check that whether the extracted file size is the same as orginial
			Assert.assertEquals("Extracted payload size should be " + Long.toString(payloadSize), payloadSize, extractedFile.length());
			Assert.assertEquals("Extracted file name should same as original", dummyFile.getName(), extractedFile.getName());
		}catch(Exception e){
			throw e;
		}finally{
			if(tarFile.exists())
				tarFile.delete();
			if(extractedFile.exists())
				extractedFile.delete();
		}
	}
	
	/**
	 * Test for tar a file
	 * @throws Exception
	 */
	public void testCompressFile() throws Exception{
		OSCommander os = new OSCommander();
		
		//10 MB payload size
		long payloadSize = 10485760L;
		String payloadName = "10MB";
		File dummyFile = new File(FIXTURE_LOADER.getResource("Src").getFile(), payloadName);
		File tarFile = new File(FIXTURE_LOADER.getResource("Compressed").getFile(), payloadName + ".tar");
		
		try{
			os.createDummyFile(dummyFile.getAbsolutePath(), payloadSize);
			Assert.assertTrue("dummyFile didn't created", dummyFile.exists());
			ArchiverTar tar = new ArchiverTar();
			//Compress the file firstly
			tar.compress(dummyFile, tarFile, true);
			Assert.assertTrue("Compressed file size should greater than orginial file size", tarFile.length() > dummyFile.length());
		}catch(Exception e){
			throw e;
		}finally{
			if(tarFile.exists())
				tarFile.delete();
			if(dummyFile.exists())
				dummyFile.delete();
		}
	}

	public void testCompressUnicodeFilename() throws Exception {
		File source = new File(FIXTURE_LOADER.getResource("Src").getFile(), "測試.txt");
		File archive = new File(FIXTURE_LOADER.getResource("Compressed").getFile(), "unicode.tar");
		File extracted = new File(FIXTURE_LOADER.getResource("Extracted").getFile(), source.getName());

		try {
			FileOutputStream output = new FileOutputStream(source);
			output.write("payload".getBytes("UTF-8"));
			output.close();
			new ArchiverTar().compress(source, archive, true);
			source.delete();
			new ArchiverTar().extract(archive, extracted.getParentFile());
			Assert.assertTrue("Unicode TAR entry should round-trip", extracted.exists());
		} finally {
			archive.delete();
			source.delete();
			extracted.delete();
		}
	}

	public void testExtractRejectsTraversalEntry() throws Exception {
		File archive = new File(FIXTURE_LOADER.getResource("Compressed").getFile(), "traversal.tar");
		File destination = new File(FIXTURE_LOADER.getResource("Extracted").getFile());
		File escaped = new File(destination.getParentFile(), "escaped-by-tar");

		try {
			SFRMTarOutputStream output = new SFRMTarOutputStream(new FileOutputStream(archive));
			TarEntry entry = new TarEntry("../escaped-by-tar");
			entry.setSize(1);
			output.putNextEntry(entry);
			output.write('x');
			output.closeEntry();
			output.close();

			try {
				new ArchiverTar().extract(archive, destination);
				Assert.fail("Traversal TAR entry should be rejected");
			} catch (java.io.IOException expected) {
				Assert.assertFalse("Traversal TAR entry must not be written", escaped.exists());
			}
		} finally {
			archive.delete();
			escaped.delete();
		}
	}
	
//	public void testCompressChineseCharFilename() throws Exception{
//		File srcFile = new File(FIXTURE_LOADER.getResource(getName()).getFile(), "Src");
//		File tarFile = new File(FIXTURE_LOADER.getResource(getName()).getFile(), "payload.tar");
//		
//		ArchiverTar tar = new ArchiverTar();
//		//Tar the file with the file name using chinese character
//		Assert.assertTrue("Failure on archiving files using tar", tar.compress(srcFile, tarFile, false));
//		
//		//untar the file
//		File destFile = new File(FIXTURE_LOADER.getResource(getName()).getFile(), "Extracted");
//
//		tar.extract(tarFile, destFile);
//		
//		File extractedFile = new File(destFile, "[chinese filename].txt");
//		
//		Assert.assertTrue("File didn't existed after extracted", extractedFile.exists());
//		
//		if(tarFile.exists())
//			tarFile.delete();
//		
//		if(extractedFile.exists())
//			extractedFile.delete();
//	}
	
}
