;;; firefox-tabs.el --- Extract URLs of all open Firefox tabs -*- lexical-binding: t; -*-

;;; Commentary:
;; Reads Firefox's session recovery file (recovery.jsonlz4) and displays
;; all open tabs in a buffer.  Requires only `lz4' (brew install lz4)
;; which provides the liblz4 shared library used via Python's ctypes.

;;; Code:

(defun firefox-tabs--find-recovery-file ()
  "Find the most recent Firefox recovery.jsonlz4 file."
  (let* ((candidates
          (append
           ;; macOS
           (file-expand-wildcards
            "~/Library/Application Support/Firefox/Profiles/*/sessionstore-backups/recovery.jsonlz4")
           ;; Linux
           (file-expand-wildcards
            "~/.mozilla/firefox/*/sessionstore-backups/recovery.jsonlz4")))
         (sorted (sort candidates
                       (lambda (a b)
                         (time-less-p (file-attribute-modification-time (file-attributes b))
                                      (file-attribute-modification-time (file-attributes a)))))))
    (car sorted)))

(defun firefox-tabs--read-jsonlz4 (path)
  "Read a Mozilla jsonlz4 file at PATH and return parsed JSON.
Uses Python3 ctypes to call liblz4 directly (no pip packages needed)."
  (with-temp-buffer
    (let ((exit-code
           (call-process "python3" nil t nil "-c"
                         (format "
import ctypes, ctypes.util, struct, sys, os

path = %S

# Find liblz4
lib_path = ctypes.util.find_library('lz4')
if not lib_path:
    # Try common Homebrew paths
    for p in ['/opt/homebrew/lib/liblz4.dylib', '/usr/local/lib/liblz4.dylib',
              '/usr/lib/x86_64-linux-gnu/liblz4.so.1', '/usr/lib/liblz4.so.1']:
        if os.path.exists(p):
            lib_path = p
            break
if not lib_path:
    print('Cannot find liblz4. Install via: brew install lz4', file=sys.stderr)
    sys.exit(1)

lz4 = ctypes.CDLL(lib_path)

with open(path, 'rb') as f:
    f.read(8)   # skip 'mozLz40\\0' magic
    orig_size = struct.unpack('<I', f.read(4))[0]
    compressed = f.read()
buf = ctypes.create_string_buffer(orig_size)
result = lz4.LZ4_decompress_safe(compressed, buf, len(compressed), orig_size)
if result < 0:
    print('LZ4 decompression failed', file=sys.stderr)
    sys.exit(1)
sys.stdout.buffer.write(buf.raw[:result])
" (expand-file-name path)))))
      (unless (zerop exit-code)
        (error "Failed to decompress %s (exit code %d): %s" path exit-code (buffer-string)))
      (goto-char (point-min))
      (json-parse-buffer :object-type 'alist))))

(defun firefox-tabs--extract-tabs (session-data)
  "Extract tabs from SESSION-DATA.  Return list of (window tab title url)."
  (let ((windows (alist-get 'windows session-data))
        (results nil))
    (seq-do-indexed
     (lambda (window wi)
       (let ((tabs (alist-get 'tabs window)))
         (seq-do-indexed
          (lambda (tab ti)
            (let* ((entries (alist-get 'entries tab))
                   (entry (when (> (length entries) 0)
                            (aref entries (1- (length entries)))))
                   (title (or (alist-get 'title entry) ""))
                   (url (or (alist-get 'url entry) "")))
              (push (list (1+ wi) (1+ ti) title url) results)))
          tabs)))
     windows)
    (nreverse results)))

;;;###autoload
(defun firefox-tabs ()
  "Display all open Firefox tabs in an Org buffer."
  (interactive)
  (let ((recovery-file (firefox-tabs--find-recovery-file)))
    (unless recovery-file
      (user-error "No Firefox recovery file found.  Is Firefox running?"))
    (let* ((data (firefox-tabs--read-jsonlz4 recovery-file))
           (tabs (firefox-tabs--extract-tabs data))
           (buf (get-buffer-create "*Firefox Tabs*"))
           (current-window 0))
      (with-current-buffer buf
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert (format "#+TITLE: Firefox Open Tabs (%d)\n\n" (length tabs)))
          (dolist (tab tabs)
            (pcase-let ((`(,wi ,_ti ,title ,url) tab))
              (unless (= wi current-window)
                (setq current-window wi)
                (insert (format "* Window %d\n" wi)))
              (insert (format "** [[%s][%s]]\n"
                              url
                              (replace-regexp-in-string "\\[\\|\\]" "" (or title url)))))))
        (goto-char (point-min))
        (org-mode)
        (read-only-mode 1))
      (pop-to-buffer buf))))

(provide 'firefox-tabs)
;;; firefox-tabs.el ends here
