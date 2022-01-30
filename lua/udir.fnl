(local fs (require :udir.fs))
(local store (require :udir.store))
(local u (require :udir.util))
(local api vim.api)
(local uv vim.loop)

(local M {})

;; --------------------------------------
;; CONFIGURATION
;; --------------------------------------

(tset M :keymap
      {:quit "<Cmd>lua require'udir'.quit()<CR>"
       :up_dir "<Cmd>lua require'udir'[\"up-dir\"]()<CR>"
       :open "<Cmd>lua require'udir'.open()<CR>"
       :open_split "<Cmd>lua require'udir'.open('split')<CR>"
       :open_vsplit "<Cmd>lua require'udir'.open('vsplit')<CR>"
       :open_tab "<Cmd>lua require'udir'.open('tabedit')<CR>"
       :reload "<Cmd>lua require'udir'.reload()<CR>"
       :delete "<Cmd>lua require'udir'.delete()<CR>"
       :create "<Cmd>lua require'udir'.create()<CR>"
       :move "<Cmd>lua require'udir'.move()<CR>"
       :copy "<Cmd>lua require'udir'.copy()<CR>"
       :cd "<Cmd>lua require'udir'.cd()<CR>"
       :toggle_hidden_files "<Cmd>lua require'udir'[\"toggle-hidden-files\"]()<CR>"})

(local config {:keymaps {:q M.keymap.quit
                         :h M.keymap.up_dir
                         :- M.keymap.up_dir
                         :l M.keymap.open
                         :<CR> M.keymap.open
                         :s M.keymap.open_split
                         :v M.keymap.open_vsplit
                         :t M.keymap.open_tab
                         :R M.keymap.reload
                         :d M.keymap.delete
                         :+ M.keymap.create
                         :r M.keymap.move
                         :m M.keymap.move
                         :c M.keymap.copy
                         :C M.keymap.cd
                         :. M.keymap.toggle_hidden_files}
               :show-hidden-files true
               :is-file-hidden #false})

(lambda M.setup [?cfg]
  (local cfg (or ?cfg {}))
  ;; Whether to automatically open Udir when editing a directory
  (when cfg.auto-open
    (vim.cmd "aug udir")
    (vim.cmd :au!)
    (vim.cmd "au BufEnter * if !empty(expand('%')) && isdirectory(expand('%')) && !get(b:, 'is_udir') | Udir | endif")
    (vim.cmd "aug END"))
  (when cfg.keymaps
    (tset config :keymaps cfg.keymaps))
  (when (not= nil cfg.show-hidden-files)
    (tset config :show-hidden-files cfg.show-hidden-files))
  (when cfg.is-file-hidden
    (tset config :is-file-hidden cfg.is-file-hidden)))

;; --------------------------------------
;; RENDER
;; --------------------------------------

(lambda sort! [files]
  (table.sort files #(if (= $1.type $2.type)
                         (< $1.name $2.name)
                         (= :directory $1.type)))
  files)

(lambda render-virttext [ns files]
  (api.nvim_buf_clear_namespace 0 ns 0 -1)
  ;; Add virtual text to each directory/symlink
  (each [i file (ipairs files)]
    (let [(virttext hl) (match file.type
                          :directory (values u.sep :Directory)
                          :link (values "@" :Constant))]
      (when virttext
        (api.nvim_buf_set_extmark 0 ns (- i 1) (length file.name)
                                  {:virt_text [[virttext :Comment]]
                                   :virt_text_pos :overlay})
        (api.nvim_buf_set_extmark 0 ns (- i 1) 0
                                  {:end_col (length file.name) :hl_group hl})))))

(lambda render [state]
  (local {: buf : cwd} state)
  (local files (->> (fs.list cwd)
                    (vim.tbl_filter #(if config.show-hidden-files true
                                         (not (config.is-file-hidden $1 cwd))))
                    sort!))
  (local filenames (->> files (vim.tbl_map #$1.name)))
  (u.set-lines buf 0 -1 false filenames)
  (render-virttext state.ns files))

;; --------------------------------------
;; KEYMAPS
;; --------------------------------------

(lambda noremap [mode buf mappings]
  (each [lhs rhs (pairs mappings)]
    (api.nvim_buf_set_keymap buf mode lhs rhs
                             {:nowait true :noremap true :silent true})))

(lambda setup-keymaps [buf]
  (noremap :n buf config.keymaps))

(lambda cleanup [state]
  (api.nvim_buf_delete state.buf {:force true})
  (store.remove! state.buf))

(lambda update-cwd [state path]
  (tset state :cwd path))

(lambda M.quit []
  (local state (store.get))
  (local {: ?alt-buf : origin-buf} state)
  (when ?alt-buf
    (u.set-current-buf ?alt-buf))
  (u.set-current-buf origin-buf)
  (cleanup state))

(lambda M.up-dir []
  (local state (store.get))
  (local cwd state.cwd)
  (local parent-dir (fs.get-parent-dir state.cwd))
  (local ?hovered-file (u.get-line))
  (when ?hovered-file
    (tset state.hovered-files state.cwd ?hovered-file))
  (update-cwd state parent-dir)
  (render state)
  (u.update-buf-name state.buf state.cwd)
  (u.set-cursor-pos (fs.basename cwd) :or-top))

(lambda M.open [?cmd]
  (local state (store.get))
  (local filename (u.get-line))
  (when (not= "" filename)
    (local path (u.join-path state.cwd filename))
    (local realpath (fs.canonicalize path))
    (fs.assert-readable path)
    (if (fs.dir? path)
        (if ?cmd
            (vim.cmd (.. ?cmd " " (vim.fn.fnameescape realpath)))
            (do
              (update-cwd state realpath)
              (render state)
              (u.update-buf-name state.buf state.cwd)
              (local ?hovered-file (. state.hovered-files realpath))
              (u.set-cursor-pos ?hovered-file :or-top)))
        (do
          (u.set-current-buf state.origin-buf) ; Update the altfile
          (vim.cmd (.. (or ?cmd :edit) " " (vim.fn.fnameescape realpath)))
          (cleanup state)))))

(lambda M.reload []
  (local state (store.get))
  (render state))

(lambda M.delete []
  (local state (store.get))
  (local filename (u.get-line))
  (if (= "" filename)
      (u.err "Empty filename")
      (let [path (u.join-path state.cwd filename)
            _ (print (string.format "Are you sure you want to delete %q? (y/n)"
                                    path))
            input (vim.fn.getchar)
            confirmed? (= :y (vim.fn.nr2char input))]
        (when confirmed?
          (fs.delete path)
          (render state))
        (u.clear-prompt))))

(lambda copy-or-move [should-move]
  (local state (store.get))
  (local filename (u.get-line))
  (if (= "" filename)
      (u.err "Empty filename")
      (let [src (u.join-path state.cwd filename)
            prompt (if should-move "Move to:" "Copy to:")
            name (vim.fn.input prompt)]
        (when (not= "" name)
          (let [dest (u.join-path state.cwd name)]
            (fs.copy-or-move should-move src dest)
            (render state)
            (u.clear-prompt)
            (u.set-cursor-pos (fs.basename dest)))))))

(lambda M.move []
  (copy-or-move true))

(lambda M.copy []
  (copy-or-move false))

(lambda M.create []
  (local state (store.get))
  (local name (vim.fn.input "New file: "))
  (when (not= name "")
    (local path (u.join-path state.cwd name))
    (if (vim.endswith name u.sep)
        (fs.create-dir path)
        (fs.create-file path))
    (render state)
    (u.clear-prompt)
    (u.set-cursor-pos (fs.basename path))))

(lambda M.toggle-hidden-files []
  (local state (store.get))
  (local ?hovered-file (u.get-line))
  (set config.show-hidden-files (not config.show-hidden-files))
  (render state)
  (u.set-cursor-pos ?hovered-file))

(lambda M.cd []
  (local {: cwd} (store.get))
  (vim.cmd (.. "cd " (vim.fn.fnameescape cwd)))
  (vim.cmd :pwd))

;; --------------------------------------
;; INITIALIZATION
;; --------------------------------------

;; This gets called by the `:Udir` command
(lambda M.udir []
  (let [origin-buf (assert (api.nvim_get_current_buf))
        ?alt-buf (let [n (vim.fn.bufnr "#")]
                   (if (= n -1) nil n))
        ;; `expand('%')` can be empty if in an unnamed buffer, like `:enew`, so
        ;; fallback to the cwd.
        cwd (let [p (vim.fn.expand "%:p:h")]
              (if (not= "" p) (fs.canonicalize p) (assert (vim.loop.cwd))))
        ?origin-filename (let [p (vim.fn.expand "%:p:t")]
                           (if (= "" p) nil p))
        buf (assert (u.find-or-create-buf cwd))
        ns (api.nvim_create_namespace (.. :udir. buf))
        hovered-files {} ; map<realpath, filename>
        state {: buf : origin-buf : ?alt-buf : cwd : ns : hovered-files}]
    (setup-keymaps buf)
    (store.set! buf state)
    (render state)
    (u.set-cursor-pos ?origin-filename)))

M

