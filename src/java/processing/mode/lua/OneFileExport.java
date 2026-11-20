package processing.mode.lua;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.BufferedReader;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.ArrayList;
import java.util.List;
import java.util.function.Consumer;

/**
 * Export Application as one program: the runner with the sketch, its
 * launch settings and its data/ folder packed inside, named after the
 * sketch. Windows gets &lt;Sketch&gt;.exe with the icon built in, macOS a
 * &lt;Sketch&gt;.app, Linux a &lt;Sketch&gt; program (or one AppImage, with the
 * icon, when that box is ticked). The libprocessing renderer also needs the
 * GLFW library the mode ships, which goes next to the program.
 */
final class OneFileExport {
  private OneFileExport() {}

  private static final byte[] MAGIC = "LUASKTCH".getBytes(StandardCharsets.US_ASCII);

  /** The packed files: name length, name, data length, data, for each. */
  static byte[] payload(String source, String renderer, File dataFolder) throws IOException {
    ByteArrayOutputStream out = new ByteArrayOutputStream();
    add(out, "sketch.lua", source.getBytes(StandardCharsets.UTF_8));
    add(out, "launch.txt", (renderer != null ? "PROCESSING_RENDERER=" + renderer + "\n" : "").getBytes(StandardCharsets.UTF_8));
    if (dataFolder != null && dataFolder.isDirectory()) {
      Path root = dataFolder.toPath();
      List<Path> files = new ArrayList<>();
      try (var s = Files.walk(root)) { s.filter(Files::isRegularFile).sorted().forEach(files::add); }
      for (Path f : files) add(out, "data/" + root.relativize(f).toString().replace('\\', '/'), Files.readAllBytes(f));
    }
    return out.toByteArray();
  }

  private static void add(ByteArrayOutputStream out, String name, byte[] data) throws IOException {
    byte[] n = name.getBytes(StandardCharsets.UTF_8);
    ByteBuffer h = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(n.length);
    out.write(h.array());
    out.write(n);
    out.write(ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN).putLong(data.length).array());
    out.write(data);
  }

  /** The payload and its trailer at the end of a program. */
  private static void append(File program, byte[] payload) throws IOException {
    byte[] len = ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN).putLong(payload.length).array();
    Files.write(program.toPath(), payload, java.nio.file.StandardOpenOption.APPEND);
    Files.write(program.toPath(), len, java.nio.file.StandardOpenOption.APPEND);
    Files.write(program.toPath(), MAGIC, java.nio.file.StandardOpenOption.APPEND);
  }

  static File write(File outDir, String sketchName, File dataFolder, ExportDialog.Target t, File runner,
                    String source, String renderer, File[] libs, File icon, boolean appImage,
                    File modeFolder, Consumer<String> status) throws IOException, InterruptedException {
    String safe = sketchName.replaceAll("[^A-Za-z0-9_.-]", "_");
    File dest = new File(outDir, t.folder);
    AppExport.deleteTree(dest.toPath());
    if (!dest.mkdirs()) throw new IOException("can't make " + dest);
    byte[] payload = payload(source, renderer, dataFolder);

    if (t.windows()) {
      File exe = new File(dest, safe + ".exe");
      Files.copy(runner.toPath(), exe.toPath(), StandardCopyOption.REPLACE_EXISTING);
      // the icon first: it rewrites the program, and the sketch goes after it
      if (icon != null && icon.isFile()) {
        java.awt.image.BufferedImage img = AppIcons.read(icon);
        int[] sizes = { 16, 32, 48, 64, 128, 256 };
        List<byte[]> pngs = new ArrayList<>();
        for (int s : sizes) pngs.add(AppIcons.pngBytes(img, s));
        try { PeIcon.embed(exe, pngs, sizes); }
        catch (IOException e) { System.err.println("icon: couldn't put it into the .exe (" + e.getMessage() + ")"); }
      }
      append(exe, payload);
      copyLibs(libs, dest);
      return dest;
    }

    if (t.mac()) {
      File app = new File(dest, safe + ".app");
      File contents = new File(app, "Contents");
      File macos = new File(contents, "MacOS");
      File res = new File(contents, "Resources");
      if (!macos.mkdirs() || !res.mkdirs()) throw new IOException("can't make " + app);
      File prog = new File(macos, safe);
      Files.copy(runner.toPath(), prog.toPath(), StandardCopyOption.REPLACE_EXISTING);
      prog.setExecutable(true, false);
      copyLibs(libs, macos);
      // inside the bundle, not after the program: a signed program ends where it ends
      Files.write(new File(res, "sketch.payload").toPath(), payload);
      String id = safe.replaceAll("[^A-Za-z0-9.-]", "-");
      boolean hasIcon = icon != null && icon.isFile();
      Files.writeString(new File(contents, "Info.plist").toPath(),
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        + "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
        + "<plist version=\"1.0\"><dict>\n"
        + "<key>CFBundleName</key><string>" + sketchName.replace("&", "&amp;").replace("<", "&lt;") + "</string>\n"
        + "<key>CFBundleExecutable</key><string>" + safe + "</string>\n"
        + "<key>CFBundleIdentifier</key><string>org.processing.sketch." + id + "</string>\n"
        + "<key>CFBundlePackageType</key><string>APPL</string>\n"
        + "<key>CFBundleShortVersionString</key><string>1.0</string>\n"
        + (hasIcon ? "<key>CFBundleIconFile</key><string>" + safe + ".icns</string>\n" : "")
        + "<key>NSHighResolutionCapable</key><true/>\n"
        + "<key>NSCameraUsageDescription</key><string>The sketch uses the camera.</string>\n"
        + "<key>NSMicrophoneUsageDescription</key><string>The sketch uses the microphone.</string>\n"
        + "</dict></plist>\n", StandardCharsets.UTF_8);
      if (hasIcon) AppIcons.writeIcns(AppIcons.read(icon), new File(res, safe + ".icns"));
      File[] inMacos = macos.listFiles();
      if (inMacos != null) for (File l : inMacos) AppExport.sign(l);
      AppExport.sign(app);
      Files.writeString(new File(dest, "If macOS won't open it.txt").toPath(),
        "macOS only opens apps from the App Store or from paid Apple developers without asking.\n\n"
        + "The first time: right-click " + safe + ".app and choose Open, then Open again.\n"
        + "On macOS 15 and newer: try to open it once, then go to System Settings > Privacy & Security\n"
        + "and click Open Anyway.\n\n"
        + "Or in Terminal:  xattr -dr com.apple.quarantine " + safe + ".app\n", StandardCharsets.UTF_8);
      return dest;
    }

    // Linux
    File prog = new File(dest, safe);
    Files.copy(runner.toPath(), prog.toPath(), StandardCopyOption.REPLACE_EXISTING);
    append(prog, payload);
    prog.setExecutable(true, false);
    copyLibs(libs, dest);
    if (appImage) {
      String arch = t == ExportDialog.Target.LINUX_ARM64 ? "aarch64" : "x86_64";
      File img = appImage(modeFolder, dest, sketchName, safe, arch, icon, status);
      // the AppImage is the whole export: the program and its libraries are inside
      for (File f : dest.listFiles()) if (!f.equals(img)) AppExport.deleteTree(f.toPath());
    }
    return dest;
  }

  private static void copyLibs(File[] libs, File dir) throws IOException {
    if (libs == null) return;
    for (File l : libs) Files.copy(l.toPath(), new File(dir, l.getName()).toPath(), StandardCopyOption.REPLACE_EXISTING);
  }

  /** One AppImage with the program, its libraries and the icon. */
  private static File appImage(File modeFolder, File dest, String sketchName, String safe, String arch,
                               File icon, Consumer<String> status) throws IOException, InterruptedException {
    File tool = AppImage.tool(modeFolder, status);
    File appDir = new File(dest.getParentFile(), "." + dest.getName() + ".AppDir");
    AppExport.deleteTree(appDir.toPath());
    AppExport.copyTree(dest.toPath(), appDir.toPath());
    File appRun = new File(appDir, "AppRun");
    Files.move(new File(appDir, safe).toPath(), appRun.toPath(), StandardCopyOption.REPLACE_EXISTING);
    appRun.setExecutable(true, false);
    if (icon != null && icon.isFile()) AppIcons.writePng(AppIcons.read(icon), 256, new File(appDir, safe + ".png"));
    else {
      ByteArrayOutputStream b = new ByteArrayOutputStream();
      javax.imageio.ImageIO.write(new java.awt.image.BufferedImage(1, 1, java.awt.image.BufferedImage.TYPE_INT_ARGB), "png", b);
      Files.write(new File(appDir, safe + ".png").toPath(), b.toByteArray());
    }
    Files.writeString(new File(appDir, safe + ".desktop").toPath(),
      "[Desktop Entry]\nType=Application\nName=" + sketchName + "\nExec=AppRun\nIcon=" + safe
      + "\nCategories=Graphics;\nTerminal=false\n", StandardCharsets.UTF_8);
    File out = new File(dest, safe + "-" + arch + ".AppImage");
    status.accept("Packing " + out.getName() + "...");
    ProcessBuilder pb = new ProcessBuilder(tool.getAbsolutePath(), "--no-appstream", appDir.getAbsolutePath(), out.getAbsolutePath());
    pb.environment().put("ARCH", arch);
    pb.environment().put("APPIMAGE_EXTRACT_AND_RUN", "1");
    pb.redirectErrorStream(true);
    Process p = pb.start();
    StringBuilder log = new StringBuilder();
    try (BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream(), StandardCharsets.UTF_8))) {
      String line;
      while ((line = r.readLine()) != null) log.append(line).append('\n');
    }
    int rc = p.waitFor();
    AppExport.deleteTree(appDir.toPath());
    if (rc != 0 || !out.isFile()) {
      System.err.println(log);
      throw new IOException("appimagetool failed (see the console)");
    }
    out.setExecutable(true, false);
    return out;
  }
}
