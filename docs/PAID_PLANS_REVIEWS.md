# Paket berbayar dan ulasan pembelian

Implementasi memakai Next.js App Router, Supabase Auth email/password, Supabase Postgres/RLS, dan pembayaran QRIS manual yang sudah tersedia. Tidak ada dependency baru.

## Migration

Untuk database yang sudah menjalankan migration 0001–0016, jalankan `supabase/NEXT_MIGRATION.sql` di SQL Editor. Isinya sama dengan `supabase/migrations/0017_paid_plans_purchase_reviews.sql` dan aman dijalankan ulang. Proyek baru memakai `supabase/ALL_IN_ONE.sql` dengan seluruh migration berurutan. Jika CLI sudah tersedia, gunakan alur migration proyek yang sudah ada.

Paket harga nol dinonaktifkan dan tetap disimpan untuk kompatibilitas data lama. Seed gratis dinonaktifkan pada bootstrap 0005/0008, dan migration 0017 menonaktifkan produk gratis pada database yang sudah berjalan. Gratis adalah status dasar akun: `profiles.premium_until` kosong atau sudah lewat. Registrasi membuat profil dengan masa premium kosong, tanpa pesanan. Akun dan masa premium pengguna lama tidak ditimpa. Produk baru harus berbayar; UI, aksi server, RPC checkout, dan trigger menolak produk gratis/harga nol. Riwayat pesanan lama tetap tersimpan.

Asumsi pesanan selesai adalah `orders.status = paid`, setelah admin menyetujui bukti pembayaran. Ulasan baru dan edit ulasan yang tayang menjadi `pending`; admin menyetujuinya menjadi `approved`. Ulasan `hidden` yang diedit tetap tersembunyi sampai admin meninjaunya. Ulasan lama tanpa pesanan disimpan sebagai arsip tersembunyi; tidak dibuatkan hubungan pesanan palsu.

## File utama

- Katalog/checkout: `lib/plan-validation.ts`, `lib/cms-server.ts`, `components/cms/CmsRenderer.tsx`, `components/PremiumCheckout.tsx`, `app/app/premium/page.tsx` dan `app/app/premium/actions.ts`, halaman dan komponen admin plans.
- Ulasan: `lib/review-validation.ts`, `lib/reviews.ts`, `app/app/review/{page,actions,types}`, `app/review/{page,actions}`, `components/{ReviewEditor,ReviewBoard,SettingsPanel}.tsx`.
- Moderasi: `lib/moderation-types.ts`, `components/admin/ReviewModeration.tsx`, RPC admin dalam migration; seluruh tindakan moderasi memakai pemeriksaan admin dan audit log yang sudah tersedia.
- SQL: seed bootstrap 0005/0008 (gratis nonaktif), migration 0017, `NEXT_MIGRATION.sql`, dan `ALL_IN_ONE.sql`.
- Pengujian: `tests/purchase-reviews.test.cjs`. Script lint diperbarui ke `eslint .` karena versi Next.js yang terpasang tidak menyediakan `next lint`.

## Pengujian manual setelah migration

1. Daftar akun baru dan verifikasi email. Dashboard menampilkan Gratis dan tidak ada order otomatis. Periksa akun Gratis lama tetap bisa memakai fitur dasar.
2. Buka landing, `/app/premium`, dan `/admin/plans`: hanya produk berbayar tampil; periksa tampilan ponsel dan katalog berisi 1, 2, atau 3 produk.
3. Beli paket berbayar, unggah bukti, lalu setujui melalui `/admin/pembayaran`. Status pesanan menjadi paid dan masa premium bertambah.
4. Klik **Beri Ulasan / Edit Ulasan** di pesanan atau riwayat Langganan. Pilih bintang, komentar 10–500 karakter, dan nama tampilan yang boleh disamarkan. Ulasan tersimpan pending dan belum tampil publik.
5. Di `/admin/review`, setujui ulasan. Periksa **Ulasan Pelanggan** di landing dan `/review`: nama publik, paket, bintang, komentar, tanggal, rata-rata, jumlah, filter, serta tombol lihat lebih banyak. Feature menambahkannya ke carousel landing.
6. Edit ulasan pesanan yang sama: tidak ada baris kedua dan ulasan menunggu tinjauan kembali. Beli pesanan kedua: boleh membuat ulasan kedua.
7. Sembunyikan ulasan beserta alasan; periksa catatan pemilik dan hilangnya ulasan dari publik. Uji hapus permanen dengan konfirmasi, dan audit log setiap tindakan.
8. Uji penolakan pesanan harga nol melalui endpoint/RPC, ulasan pesanan orang lain, status belum paid, duplikat order_id, rating di luar 1–5, komentar terlalu pendek/panjang, dan markup HTML. Percobaan keenam submit/edit dalam 10 menit ditolak. Jangan memakai data nyata untuk pengujian penyalahgunaan.
9. Sebagai pembaca publik maupun pengguna lain, periksa `review_feed` hanya memuat approved dan tidak mengirim user_id/order_id. Query tabel reviews milik pengguna lain harus ditolak oleh RLS; akses anonim hanya memiliki kolom publik dan baris approved.

Pengujian lokal: `node --test tests/purchase-reviews.test.cjs`, `pnpm run typecheck`, `pnpm run lint`, dan `pnpm run build`. Pada runtime workspace ini gunakan `--config.verify-deps-before-run=false` untuk menjaga pnpm tidak mencoba menginstal ulang dependency. Tes otomatis mencakup validasi dan aksi server dengan Supabase/provider mock; alur database/RLS, email verifikasi, pembayaran, dan persetujuan admin perlu diuji setelah migration diterapkan.

## Hasil pemeriksaan lokal

13 tes otomatis lulus, TypeScript lulus, serta lint tanpa error (warning lama tetap ada). Build produksi lulus; sandbox Windows perlu izin filesystem tambahan untuk `.next`. Migration belum diterapkan ke database; PostgreSQL lokal tidak tersedia, sehingga RLS dan alur pembelian nyata perlu diuji dengan langkah manual di atas.
