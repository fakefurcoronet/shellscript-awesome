#!/bin/sh

# --------------------------------------------------
# FTP connect tool
# --------------------------------------------------
# ftp-connection.sh
#
# @date    2015/07/31
# @memo    crontabの記述は「00 07 * * * ftp-connection.sh 2>/dev/null」といった感じ
# --------------------------------------------------
# データファイルと件数ファイルをFTP接続で別サーバより取得し、
# データチェックの上で取込み様のPHPファイルへ受け渡す。というスクリプト。
#
# 取得対象のデータはデータファイルと件数ファイルがあり、
# データファイルのデータ数が件数ファイルに記載している、という仕様。
#
# --------------------------------------------------

PATH=/bin:/usr/bin:/sbin:/usr/sbin:/usr/local/bin


# --------------------------------------------------
# ftp server setting
# --------------------------------------------------
ftp_host=ftp.test.com
ftp_user=ftp-user
ftp_pass=ftppassword


# --------------------------------------------------
# directry & file setting
# --------------------------------------------------
# get_dir	ファイル取得元ディレクトリ
# put_dir	ファイルコピー先ディレクトリ
#
# FLG_FILE1.TXT		件数ファイル
# FILE1.TXT			データファイル
#
# --------------------------------------------------
get_dir=/E:/USERS/123456789
put_dir=/var/www/cron/

file1_flg=FLG_FILE.TXT
file1_txt=FILE.TXT


# --------------------------------------------------
# backup setting
# --------------------------------------------------
# bk_dir	バックアップ先ディレクトリ
# log_dir	結果報告CSV格納先ディレクトリ
# bk_days	ローテーション期間
#
# ts_now	実施日
# ts_old	バックアップデータ削除対象日
# ts_old2	バックアップデータ削除対象日(アンダースコア区切り)
# ts_prev	実施日前日
#
# rm_report_csv 処理結果ファイル
# --------------------------------------------------
bk_dir=/var/www/cron/backup/
log_dir=/var/www/cron/log/
bk_days=30

ts_now=`date +%Y%m%d`
ts_old=`date -d "$bk_days days ago" +%Y%m%d`
ts_old2=`date -d "$bk_days days ago" +%Y_%m_%d`
ts_prev=`date -d "1 days ago" +%Y%m%d`

bk_file_flg=FLG_FILE_$ts_now.TXT
rm_file_flg=FLG_FILE_$ts_old.TXT
bk_file_txt=FILE_$ts_now.TXT
rm_file_txt=FILE_$ts_old.TXT

rm_report_csv=report_log_$ts_old2.csv


# --------------------------------------------------
# mail setting
# --------------------------------------------------
message=""
subject="error report"
message_flg=0



# ----- 処理ディレクトリへ移動 -----
cd $put_dir



# --------------------------------------------------
# FTP connect
# --------------------------------------------------
# テキストモード、PASSIVEモードFTP接続
# ftpオプション-ivnでFTPのログを表示(デバッグ時)
#
#    ftp -ivn $edi_host << __END__
#
# --------------------------------------------------
ftp -n $ftp_host << __END__
user $ftp_user $ftp_pass
ascii
epsv4
cd $get_dir
lcd $put_dir
get $file_flg
get $file_txt
bye
__END__


# --------------------------------------------------
# file check
# --------------------------------------------------
# 件数ファイルとデータファイルのダウンロード成功可否を確認し、
# ダウンロードに成功していればバックアップを取りデータの確認を行う。
# データに問題がなければ取込み様のPHPプログラムへファイルを受け渡す。
# ファイルの確認手順は下記の通り。
#
#    1. ファイルの有無
#    2. 件数ファイルの行数確認(2行以上ある場合はエラー)
#    3. 件数ファイルの更新日確認(前日か当日のファイルのみ利用)
#    4. 件数ファイルの件数とデータファイルの行数を比較(一致しない場合はエラー)
#
# --------------------------------------------------

# -- processing 1 start
file_exist=0
if [ -e $file_flg ]
then
  cp $file_flg $bk_dir$bk_file_flg

  if [ -e $file_txt ]
  then
    file_exist=1
    cp $file_txt $bk_dir$bk_file_txt
  else
    file_exist=0
    message=$message "\nデータファイルのダウンロードが正常に行われませんでした。"
    message_flg=1
  fi
else
  file_exist=0
  message=$message "\n件数ファイルのダウンロードが正常に行われませんでした。"
  message_flg=1
fi
# -- processing 1 end

if [ $file_exist -eq 1 ]
then
  rows_flg=`awk 'END{print NR}' $file_flg`
  rows_file=`awk 'END{print NR}' $file_txt`

  # -- processing 2 start
  if [ $rows_flg -eq 1 ]
  then
    read line < $file_flg
    file_update=`echo "$line" | cut -c 1-8`
    file_num=`echo "$line" | cut -c 9-15`

    # -- processing 3 start
    date_check=0
    if [ $file_update -eq $ts_prev ]
    then
      date_check=1
    fi
    if [ $file_update -eq $ts_now ]
    then
      date_check=1
    fi
    if [ $date_check -eq 1 ]
    then
      # -- processing 4 start
      if [ $file_num -eq $rows_nouki ]
      then
        php update_file_info.php "/var/www/cron/FILE.TXT"
      else
        message=$message "\n件数ファイルの結果($file_num)とデータファイルのデータ数($rows_file)が一致しなかったため、異常値と判断し処理を停止しました。"
        message_flg=1
      fi
      # -- processing 4 end
    fi
    # -- processing 3 end
  else
    message=$message "\n件数ファイルに複数行のデータ($rows_flg行)があったため、異常値と判断し処理を停止しました。"
    message_flg=1
  fi
  # -- processing 2 end
fi


# --------------------------------------------------
# backup rotation
# --------------------------------------------------
# ログファイルが溜まるのを防ぐため、定期的にファイルの削除を行う。
#
# --------------------------------------------------
if [ -e $bk_dir$rm_file_flg ]; then
  rm -f $bk_dir$rm_file_flg
fi
if [ -e $bk_dir$rm_file_txt ]; then
  rm -f $bk_dir$rm_file_txt
fi
if [ -e $log_dir$rm_report_csv ]; then
  rm -f $log_dir$rm_report_csv
fi


# --------------------------------------------------
# send mail
# --------------------------------------------------
# タイトルと本文をメール送信様のPHPプログラムへ受け渡す。
#
# --------------------------------------------------
if [ $message_flg -eq 1 ]
then
  php send_mail.php "$subject" "$message"
fi

exit 0
