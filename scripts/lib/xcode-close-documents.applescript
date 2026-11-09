-- 撮影のために開いたサンプルドキュメントだけを、保存確認を出さずに閉じる。
-- 利用者が開いている他のドキュメント（未保存の変更を含み得る）には触れない。
-- 使い方: osascript xcode-close-documents.applescript <sample-path>
on run argv
	set samplePath to item 1 of argv
	tell application "Xcode"
		repeat with d in (every document)
			try
				if (path of d) is samplePath then close d saving no
			end try
		end repeat
	end tell
	return ""
end run
