-- Repair the 230 legacy public.curvy_roads rows whose region column is the
-- empty string. Every one of these rows was classified as Quebec by the
-- read-only Statistics Canada 2021 boundary preflight with zero ambiguity
-- (230 unique targets, 0 null regions, 0 writes), so this migration writes
-- the canonical legacy region value 'quebec' -- exactly the value that the
-- later 20260716043420_western_route_publication_v2.sql backfill maps to
-- province_code 'QC'. Without this repair that backfill fails closed on the
-- unclassified empty-region rows.
--
-- Checksum bindings (authoritative empty-region repair preflight, 2026-07-16,
-- re-observed byte-identically on 2026-07-17):
--   target snapshot (230 rows, sorted by id) sha256:
--     e586c43de9425a47c54f20d0b68fb8a3161aef264e5771b47b152046fd999217
--   preflight report sha256:
--     bd67d66361b572f023351faff9aacab72ad5210181de477a903148e8c9945dd9
--   ambiguity report (empty) sha256:
--     37517e5f3dc66819f61f5a7bb8ace1921282415f10551d2defa5c3eb0985b570
--   checksum receipt sha256:
--     a43b91a50c84a846bd759f2111d32bf2b7e61995fc8c446cd5e6d916ede63c67
--   StatCan 2021 boundary archive (2,777,186 bytes) sha256:
--     c4dd830f8a6e9b4a1d80e71bc830ae319aaab37785cc92185e830f5e3da4714e
--
-- Fail-closed contract:
--   * The 230-row ID receipt below is immutable. If any receipt row is
--     missing, holds a region other than '' or 'quebec', or any row outside
--     the receipt has a null/empty region, the migration raises and the
--     whole statement rolls back with zero rows modified.
--   * A completely fresh database (no receipt row present and no empty
--     region anywhere) is a clean no-op so the full migration stack stays
--     replayable from empty.
--   * A re-run after success (all 230 rows already 'quebec') is a clean
--     no-op, not an error.
--   * Only the 230 receipt rows are updated. No other row is touched and
--     nothing is deleted.

do $$
declare
  repaired_region constant text := 'quebec';
  receipt constant text[] := array[
    '00a24c7322ea4429425ac6005ef1790e0ce2a9ed07ca7a5bdbca05b6bde55448',
    '0130a96a1c2b48f1af41665cacf93cde48d086421d7895dc45db854c4ccca0cc',
    '01e03df2661153c862003a2858db77cea21efc8ca8e60e0169ece6c67e5f701e',
    '027b8d5ab62d382794a772a139aa0b4b90e9eacb3d9ac0dd368246e8e938244e',
    '032d5d0a772485a67c8453e9d0a513429e101d7f68d1a54f1e4bbb658bad93a9',
    '03731eb5d38b56f0088b3996f71e8a399ee15c12a2aefdd375c33777c09d0804',
    '0377f31fc0b3bdb4734855b64abc58ddd1a8bc565de18092ede4fd1aec295c46',
    '04775a1080c36451b5f49a671a437faa249c31b90c168a977aeb670b38ed7a04',
    '04f2d64be98186b5b2e008866d3561352bccb533f4b7012209e776439f8874fd',
    '05763df4bab5e855b9ad0ffe79e094be114838626dde4f63a68c1c83afa5d23d',
    '077bcb8df44c30522e59eb4fe9cc19d9b3e58d4dafe57d89966b742b0ccf10ad',
    '07b0292d347ae5f48077705079cc99b11a268cdee743b685eb0ff2b7b865dba1',
    '096f084d3b836818ccd1d740b6978ba3170c4092ec90118751f2ff73035f6c6b',
    '0c35ee31a067de053b976f068686343133a5c477687172f7a04a9079c6960073',
    '0c5be3c246a828443b105163b3530d9e33d39c03fa6e443329013936c82b62b1',
    '0d956cfc351a5529167693a0b051b1906d5e8b4d6daecb2e5ce40709b4ea34fa',
    '0f0cd444b847a1846e5b2bbc0430a7b72ef1e39bc9540941f712333ea07e0870',
    '10f4887db2d71cffae704808bd1c8f6dce51cd0f80a4340da7c25e51f0d5a840',
    '123d8bbbd5be9848365a98656258f1ad964952508657acdb030e6cd356ff4bbe',
    '134c2e7cb43000423376016ea13b7eb92c7d60ae0c4f5fccf12d01a2b8013151',
    '143cb358e72dd70719313c90f6f650b9dbd62b60f8f31f2d0b30d5dd9cedd025',
    '14d7d8804907c775e5cffe1f46af90149e32841365c45b66748aae5469f57f96',
    '15ca5bea2ae79c9d8a32380f51417dfa0dd339397ae4b04664e21daed9dee75a',
    '16974b7896719e0bd69413424780f480960797b75f80f831ddf5c484bed182a7',
    '16cb371e7c2a9c3b9f8c385e6af4398d225f9be7cbae59248a65610f9bb6aa44',
    '17bfb5019087183c6850679505c67a5a7dfc00dd256cf2e82fc23eb7097b8ef5',
    '194f66443786879797c8ddabd8c920d1f7f164b6d3fce77940ab62cb8716e068',
    '1be1892f22cc32c028fcc813d138ab2daae1b9b27ac8ab1a6e4b1aa2e7457557',
    '1d45ad1c33cb488dad0f44fe030eecf52670fd7c4e4bed59b44e7e9331eadf32',
    '1ddc06d7bee98b5811ea2b6e90b09f7480adb576b7d9e707a173d41a5879358f',
    '1e8b3f072e4a5d16af07ecbd98798d61740e6476e397bb57598f38303cf5bacd',
    '1eabbdae3ecfc2804defe3dcaacb2360d4115c7b3d846827f92a4597888760cc',
    '22c05c2dc46bbb673e87f0e066c79e960f69d85ba8f4a2df2056cf5f3b86b273',
    '233cdbbb883a28d5a9775d1ca8ba744f45af5c60abd932ef520296d5d4ec114d',
    '241b3fa713678067a502b6b6f3abfb584f89642fc005d459b210b02edfd16f5e',
    '24453e247e458e1255752719c0210739c670833e055bb4b907b7164ff82efb91',
    '24997d7d57bd52f6dde1682d2165fb992958015ff044cfc0f5d10ad9fef95c2b',
    '25c163ed72d1d8dcb92d70acd1020a40810b68bd19b13f9038254d16c72ca2a3',
    '28051c8d59903732c32eea506a1ecb700949e6e1b17b1bb2443e3b67ae6f7a50',
    '294a2adca56150cb7e08204679416ac0e4586d232cc6bd77af6a92045db3f879',
    '2a2b9eb43b9a153fd7281f4ac06ea7a970ac25fec85e58bbef8230f6afc76ae3',
    '2d737f0a5a64199aa04c0f9b2cc288b25151e4129a6f43d409cf59c6d08122f2',
    '2f36fe21beb181ebfb17c7f00275897b37a912407ccb5ee2eb7826c4788e33b2',
    '2fff25ae001dc49a4c55ef370014f0cdbb35866c5f5f8e0bc0aae9adcfd79c29',
    '3165b1b4c4c0783969c940e721e531224b82aad0ad1b4c4f9771590dd598cd6b',
    '3301ffa71082e40a3aa200ff07b7e8d9d53c7a73ee105fbd98bec03367174e75',
    '342a68c509446affb79730ed26e1fea990f8a154c975640714e2b1cec01c49a7',
    '35735cc488e81695e710ee97716f5796508b3cf80ccb49d31bfc789792b01674',
    '36da0a0f11dfaf5d27ab4e9c3605a172b729c5288b73f0cffbad57c10b6b6d6c',
    '387b0caf0a72261a087979c29c91a4fdcbdf967b523f99d6e5edea843131f0d3',
    '39a7a8b6b496a61d634ff4e9dbc4312169fbba0de2178dde6c792a0a2a21f5f0',
    '3a10206b6c8d1441a36da771314b1227b6a05c3b7044a9c92bf5df3a02dd676c',
    '3afd7a91c7643a15a44e4a52a3a50f24273f3b61b69e4d65bf9a71c79ce4fd47',
    '3c8b2e72990801baa6fe60bcd243ff3e8ae3494bd8fc60e00f896464358bfc69',
    '3d148b8cf08cc9d7ae5e77e390abe2001c0a6791382e9dd4072f505e64313e94',
    '3d2e8dcaacb0c79508f36fcc91abf6fa92f98183c02c389426e34b537f72c65d',
    '3d6e9760ca1417fd0d0a8f14b018c3dad1bcb0e899c905d0663553059bbc53e9',
    '40142da3d2964a6f7f413c6f43320fa26ede1c3a82ccca3c2f55bc06a22cf47b',
    '41781f720f814a922a1b730897aa91e9002e01fc7b11afe5359e46634687010a',
    '42df940ee865ee026355f29ae66a1df32392e864853609321fa363ca2de08b47',
    '43e119a7dce40b3cf8ee801fcf1abb9216daf67eef23d943a807bc972e322e06',
    '478419463134cf7dd6a2c85493794372df3221e7255708325be2660d9c33ca25',
    '489c114a3b26f0ff41baf72aa9abb3c3db5dd4dc113701b688ad22e6e6abf2dc',
    '48f0efab963018500b57077ed44e097d53d29a968fed97554ce9d35897c3c941',
    '495fb148de6474fc0c345656e85bb9044ee34f5c67bfc0b8f08ac96b85559d71',
    '49a458f6285bebfe3fb1f47a3c778ba0f53ac7dc4c3b6393ada7d124f11f54a7',
    '4a238279358a4ee57973ff0124ae49fb69682c3fece1aaa862b42553b2e9fc27',
    '4a98faf7ff54b96cba4820f6a296e7931955155fd5382f8104fdaaf9fe88dba1',
    '4b21a675fccd306ddf6a407aec33852e5d333db633939e2595be83a350779aa4',
    '4cc5432bf31153973dd033958278ea81129bf46edd7c9bc492b163b0a48edc85',
    '4d274e68b880c54a839acbb04ebfa917e819624f63cc50d0289aa783005b2fc7',
    '4e38996391eecd7627282b502cfe80b4ad3def62bd7753581536d72662b10199',
    '4e69232b5fe2761adb2e3b17995dd582c2a86480e51e7d69d9665945ed8535e1',
    '4e915704f45830babb36422b2010ed9a2df122e4fac28886e14175239173460d',
    '4ea0943360e3261f39f949f971a9dab13db4ae55a98670e5d2eefa5daba6bdd3',
    '4ffbf38199e4f2560b2fb0d9b8be0c8562296699042c258ac214b2d3e22f4fa5',
    '51bc80651cb2cbb1e4990540561abc19c98222b3720e7357617e507a41a0f7c4',
    '54df7af3efb271024874e5450b8f5c02a68096bd031f89ae6230233df36d069b',
    '553dbaede1c397247a6af5ea404b40cd9e11258a4ca0ad2b828f37d0d9a89b41',
    '55e525e571c5280e4c8760b71c6db0b6e23e92645c46712987dc7b4f714acbc4',
    '579cd520f810c1d5910775d731fdc3a8c4ba84d176da009e1021b45fe23ce6c4',
    '58ce295f363f376bc1f4b7bde13c7a4f614660c86b593afa4bdd5742f5bb5b4d',
    '5ab748412ab6c41d2eb6d8db5bf34e3bbcea095f73872ec281bf374ab4507246',
    '5c0d7136f58827b8db8b19413a1bcf208c67ca860c352059aa1ddde5a116931a',
    '5d6a61b545cce2219884a3cd7c86b275ffc8df068e24a1baa09b16b73c5bdf95',
    '5e6f7adc200c926bc7bbd5918e60519fd5313370490f853e6e5b78a257b324db',
    '6084b4998ec0c59b2adb9844779707a62b27d423c01f3e87b6c62df381ac77f0',
    '61258b2960e45c4cd5c35f6c4d9280e01f74adc2f00203e4609bf47395ef5221',
    '61b604c5c392ece9b9604503535b58429bce0b74626bf3d29e42a1a16bbbf251',
    '63306d7b176877b705e91bd2fbe81ebe0d1965c627cfe54f3fbafb5d8c8348f8',
    '641897f0695b96388f7411fe66b9a152e031bf682e0bee2579a99ac6ca0289ad',
    '64606985be3e732e9bdc9fa3f8a2f643bd67b968a424af4ef0d4eec81f32e47f',
    '652eb6989cbb93ec61609277b14f2f595be92235eb3b482d2be0df296d21acb4',
    '6582552bdca23db845a0b11e09c1ee0530286092463f29dc3fb30b754cb9f1b2',
    '6763e3f581e2df883fddc0620489496d94eca0019a3a7e37a6c9a9f4e4735171',
    '681dcf2960192012da237f28b828e59ec4198ac0c42d7d964a90faa24c0facec',
    '68b78b20875519c92f868813ea9424ed0d01c8c795010ef10a52d29f5618b711',
    '68e37e55cb8ff8f47e9e47cfc05fdc2b650a0899d4b738a9894f27fe81e005c8',
    '6903b6f2763de7d35ea302815609efcbb9c701f51abfea295ae625d3e977fac8',
    '6afa1b6030d01f3d95622fabfd0533a077fca84a030848dfc1f367f3e3dd8de1',
    '6fcfcbeeaf05429055c8050356a71889fc3f49d05fccc0e33657636dc0c8d2e3',
    '70fcd47ce2892c33fe672054e9ba911ed1c64fcf72e30ad41ebfcf65ed65d5ad',
    '728d373ad4254c62c4e05d17c7b4ee1a1cec1e7d7ebe4d3780231970e0291d0f',
    '73b2e877945bd108cca593b17464a55526fea92f909eb37ae8ce90b704260f36',
    '7439839b99c26e03fbb3147acc70ae72f489a1655e19065b20b513a4a4092eb3',
    '74f685899660afbbf5989b2c8ed406c57f68d8e8cac591e4857c80d8803328a9',
    '7545d55a9ee751c4a8e7cce77dccf28d534081cf53c4b4f7a91149803cfd93e9',
    '765f5796d492f566ec1cf68fa98f70630ac7d9a410ad943e9935c54b45db2803',
    '769f75bb02ac69aa3b34cb490311fbefb8d60925b808bbdc935bf1eb07a8eb01',
    '7b759c3a74e30677b705d68cbe62a5638d6aaf5a37fb4055c0582f053a0aa332',
    '7daae46f571efed20fc26e53e7cf70a81b406475232f8415ac380f1db4d93d31',
    '7eb8870c8baeeced43eabb0003418685f9c4b7cb9f649976463781f054cd3ce9',
    '7fc586a87df7263f15df728f55d31458c01e78cf81aa4c2c36d1bfe81d1c36c9',
    '82730aaf232b24dd84753f500aace124a926e11f1ddac20288b263e1946a2fe9',
    '83cd24e3b6fae2f9cb488cc42f10a9d7b30aaf517bb163590e4982fc3d512023',
    '848545c70443c09ebed13be61580ee4216c6fb613d5111c5de8661eb66ae6f39',
    '84e63aa7d53ba70122a1dfbb0a8e281b02b4a1ae4c46dbc7657774478ab952dc',
    '85d9413c07a236e9646fef63a881d33d34e43a249485e1b9f97dc29783d1202b',
    '8677f7fc40142e7a839c61cc13e2662ef6083bda0da7a6f3521e350089ed7591',
    '868d300d09e631aae20e5e66afe4b9c7af36a6b6075fff974ef62dfd07006eb6',
    '873d97ec1f286b6ac2114cfe2a6e0b432ae48354d436c6f7d45de41b9fbb3c1f',
    '87415df37e1e087221740f667155596d7097095283fa7557b7e92656ceaee257',
    '88f476d4569a84b67f2b62810245235e04f396bdf059059dfbd4a649c5efe115',
    '8c342ebfa307edb5238586d14a1d83a020d4ff868394c6a561d66e795f494c06',
    '8c4fb39d36af99b6d4c7a1d5c91bd3d81d1b41793a20182233b4344ce6e02fdf',
    '8d3688bcb883213ce5d89e4b9cf8683254fee4e044dd345ad562396cdbfefb85',
    '8e96533a70bae93889fbd4c887ae330b2be0d1e1f5da8cf62742e8a1bdba95e2',
    '8ee8b1219351deeacd63ca373b9105caa5b128f34b553404c24816b538c992da',
    '8fbe44d57c166676776d6bb1111e09427653be5b457d1ac7036d2d23eda90ff5',
    '8ff5b42f72f16681ac61ec6b2ece0ae2b2463dbce3363a8be495650431a51294',
    '92688cf2a0c68230b3ad38342399aae058b9647c3dda4a18999efc30a22a1775',
    '9331e7d68c0540542372981b2e60b5d43c4d69761c38fca75db0e8a2a990a748',
    '93e6bf59d9c7fe3becb49f608ce00537a82c8180e75874589f2c1e2a06f767d3',
    '940e6076ffcbf1d7b0acc827446f6ce7316d5712c189c72c5389b26eead7e3a3',
    '94a58dcdb819bd4dfb2724d4e8bce2c8e07dd31c4cdb1999c7f5bc56b859dced',
    '94f510aeb53b9189081910fb811f747536464690d9e3817daf20e6d35568c542',
    '95f8c12450e039e3dd601f3613cd54ba2b17e198c5bd03fa3f5e6e2df0e85e71',
    '96ceba587729a2ab4bab90915adfb0868e52ffc52b0a68315c80386c0ab782a9',
    '9a72a4eba3981f0fb7e2a8328618b5e506e4e53546e8bade9c5523cb97acbe04',
    '9abb4a0dc0bf61a5c010d5ab8f9c46b3f5a085629f6f0161bcd8915acc29c1bb',
    '9abcc50513e81f887d8f092580b34b07982c4ffb7dbb100ea71e71105208fe5b',
    '9bb83859093b3bb63487e9a4e08c564dd42e066c4be25ded2470a126824e77ea',
    '9cf14f6f4862579e421f5dcf4ef4dd2d8f41c712bd7f9ce1e53c08a36137d0ec',
    '9f2c886e119fcc34591ff1efd4c3c8dda5af062042d8f7fd821c91a3e2e5253b',
    '9f89d231fed7b56dfa3d95847fee53f0a10b0d81ac03712c9f64a069df289bc2',
    '9fe1b8c1c48f0bd710ea0e90824ec2ab7c9c882dbba87b91a628d398b37cf2c8',
    'a04624df7e3549332309fec6671e272a5d1666089e2b91600e017fe443de895c',
    'a3e5138c34f1b7c755ec43bcba4f970397893dae89ac104302effe07908f9624',
    'a4f98864fcbacf1d585ec1f3794f1feb1e25a6b89b99a8d352ef9cbb564099a6',
    'a53826d5bb2e2a05e5a4ccca291002c511b3a9ff1e29d92a678304a965d1ac14',
    'a80fe1586e3b42059bb0db6798685e2656c578338abd8e479cf4ac089a733b3b',
    'a81098c9aa9adc3e949b9d97d88b8c9482103b29e8f969596616f94776b3e0e5',
    'a97d075a4fa8622b582371a3a753b2ad11e0cd4449b64e5fb56830f9cef61c28',
    'a9b9d651a2dee6bcf8d98029bd720f955b8c1d1e7bccd895334a048cc1dfa01a',
    'aa92c709ceeab34fb302b7539f99ead4b62da7b02cff077361e489dbdc02f01e',
    'aae33ddb1ca5c782ea56f449cd62f7204c9b8f19a71dd3b5851c78b1adac7df9',
    'abb8b2ce28d2ba7f45f30084ac15ea2475cbf8b26bd66f1283fb810094252598',
    'abed21a0ce8b3f495ac7c2b93277de43dd1771c15931be5bd2ceb2d95c5fa871',
    'ac79902beed55d22ab46799166dafee6b322b1ac35bfe974610eb168d28aa7c7',
    'ae1860fb9c615a5968ea2b8b80cd0cd41c2d0c44b450817a40af42bb7bb80a2d',
    'af1674cac3f2b8f5a57d1969cf456f654fb2f8dbf40ffd2e5d268cb95207861a',
    'af8ca67d67a2e17d7377c336477d585b0dc0f2308576ad3758f70e715262869a',
    'b08539300efa070db0d6b81e09c1fb18b775e619e94515e447c1138700029498',
    'b24ee62f78569066b7b2d0016ce81732796d4b9606b697c2cf0f8d4a1f285049',
    'b29b407590a7ccf50329786fe167926c09c2efee8f224f4394bd7ab63b116fda',
    'b30c658b1ec5910348ef047ff42bcfae08a5b95130a4d343fac0dc14248ad4e4',
    'b67085cbeaad190f0f08c0db3365d07bbeaf4306b5da6a34093e39fd97b63d63',
    'b69946de00e6625a495b7eb19210351a52797f79b660e0f4925c34e38f796266',
    'b882dec40577b5e89780027a9b96db7a52202f85278a931ccab6b5642d0a81f6',
    'b9dc826fb6c10e6968484c4d95f2f9427b291cf42cc5f84e25747c69ef1c0ec9',
    'baca9f013e967d8b92b8c123d58a0d9430bd2b6fd2ed41c1a72a3894c2dee03f',
    'bb06b3531676b52c7ff647c50d9cfd4e723ff6404fb4dabfbedd475675cdcada',
    'bc093e1bbb451c6ea1c8ce912283f9f9fcb3d47978f624505601acfac6773506',
    'bc39dc9f401bce78d937d850cb2c1f57ad70963f7db76b7b5918a90cde6e779b',
    'bca783d311cf0db9dcb336039796781358e2af3df96374c6ac3e7c7d15333d59',
    'be8418f000c73be820d8a7e2de7adb65dc42c0468a7e2ffc312b06924a03b2ad',
    'c0b3d6b22f6a676728830d012ac6beee40824b3c863c3e2de77fa7b49f235542',
    'c0f07b489fc1fa467bcf0244e1348e2f0aec88b378c91480e711715c18c0d4cb',
    'c161d202944fb5b59c70b333cd0403feda688f7a31da17e1af058d3781fcf4b5',
    'c8b2bbe4d595bb0802fec9c324c8b4cba7b643f3bf344e0ed287644600125e61',
    'ca60346bfc2a0954c23e5d3fbf3a1029e6b6ebb24012f263f61e67cd46b32043',
    'cb4a356acccb984e089fa32c8de7b95900b4969bd4389ce3fa5c6523ceac4a1d',
    'cdc7ed67ab9dddb987ef2c3f97e697ac8e0dedc3614f51003e6eb410d2e115cd',
    'd0169193b8b728064cfa62712f0495dc061da1a51865567ee8988b95c6de61f3',
    'd08833830d373101a05a8c1b08c7575fdd972ec256e83ff3979da2def08a9467',
    'd2d044fc3c04a71f8d72481b9cec30b88990fb576b33dbc3dfb1d1266e386243',
    'd37bedacd1b27d73820c2b4f51940c08009c71299f95df24146477f7fb1f7790',
    'd643d27c0084415edcac41d241b3b822bb1547052a91d1580de72a39c5197e22',
    'd70124f8d7ac82407c090af98ee5f38c60e0c2faf89666c1d7e202b2f0bc7ebc',
    'd8a08fdd50debf614074790f5bdd8ddc45215cb89ee0d1702197a5b0b139827b',
    'd9ed708bea5b1527100d5926dbd58707e9fc211ff22f221c417db226e30f8853',
    'da70dc7394840330197857b7fb8a1b96c0ac9cbbc81e90f25bb601795313d7ca',
    'dbac2df36ce41e90aac6e87abca0e162098e89a4d5643e510ed7c33c98d85403',
    'dcfb8fafa455b1311ab296e4a1101365e11302d24016f212249d70e1f178d682',
    'dd0b546494d0d1a568db49c33df637d69ece9d5f5f5fc11ec9a88a7707841e21',
    'ddeaa26b769c1df38fe64d0ea47f4fa4fc976054fb977851ba59c95431418550',
    'debe2b515b99374ce18eacd4dde0c09cf26f42733fc0d4c93e5b0a732019beb5',
    'dee02450f73fbffd6cec6abb60b4089e776ed8ebd1b9b3087d60debc80c4219e',
    'dfc153be54912e58945ee6076ca53c1fd76cf3c8d8f0beb724825d97d5e01fea',
    'e246baacf3975d80f5dafe44e13eeb3b4e2353066b89c14f4a7a4b7839c08667',
    'e3a492a02633e94bf8888a0f89fc883c0c0d26e3c145d23604f44634d7ddea67',
    'e3e1a5225fec1a9d8de5df26785a6a22c13cfe5a1dc43108b33831ba2fc52b9f',
    'e65e7404df5b88dc4497debf569922290d3e4113f8f5b3462b514da80c12e682',
    'e6f4e39bc20cb08cd3df084b473bfec95aa145740c2b1f7c79748a7f59c0399a',
    'e7727e67dd96cbd7929d9512b5b81549f1225395dc0f515f9c24d687e068330d',
    'e79b76eede61c6290a2cfdbc66c2c3fd1dc1a6807750049902c40db8dfbe873c',
    'e7e7612ca06eb4977d9b7af370c645f2818889868d6447b5087a0dcaa4ce2542',
    'e9b6bb6363fa33be3bebc991dd86e3111f690758bfae9de860e91796c07d9f35',
    'ea3c85ab515317889bd7b912223fd9599174573bb2cdf1ffc87fd656d4f02665',
    'ea9315be6ad5da66b5b22561d35de5d7348f188c4bba88d20a7efc7e163a9beb',
    'ec87ac174e3c0263d067536e354e98b2cee4bc7b8c24a06ad2580334f0d6c858',
    'ed3e2d7074a84261690a02fcb88aa2cf7c8e65547b93622a09a9dd2b26013796',
    'ee7c0b7f7374cb6a27caec2dc11add09e51492a7ffd39fbd814f709207dd68d6',
    'eef708382d2baf1a0adcafbb69a6f98a147da420f660520c5f87ef275e6ee721',
    'f3726ef6fb56b7af05d069d733580b57d9fdb9d6502a2194cb311c97dd768cb9',
    'f3a3d198e67cfbefbe2e21cd7409870a306374a097e07435f2acd43e0745befb',
    'f3aa6a7e1278005fc557fc39cee08ba0e520141a1b5eb0c9ca8a47c48964744e',
    'f3faedd6b4e85ed514927f51efbad3282387c38912a3e2c37d42a782871885f3',
    'f4022fb5e1e69c4ed79eeef515edd345381d52028df8d5bffed93988c55c0cd9',
    'f432b63922b7070a60093e2e7d15eaf2565b9e1d96400471b9caa5411e0d3789',
    'f4a469bb371452e534b58759f7d0c9c5ef163d2fc238836f235ba29497646bf1',
    'f60b312e7028f364f2b4aafa643f4a44822965a53a581ebd6e0c6f1a5e3ce71a',
    'f60d3eb3253ee11897aceb7aaa1775a5101bbaa1c9c82e65e454d5fd1b09c81f',
    'f7172c51ce79ba55b48651ed7bc8b00269f224262398c0482d7422bef7d87854',
    'f7dbc80b893b508b96d1409f8f39b9c6d5959929cc4fad6a856d7ba0a8c2533e',
    'f93ed9dcddafa5e5ed66daa4ff40042cfdb15274ac575f052106cd36183d3674',
    'fd92f439d1a5389843733b86fad77fb68b3c849129f023381e8f54c800ff0449',
    'fe089804ff215d23d7b4d39429b0c631293b3de48f713aad53905571597c4685',
    'fe635bf11865e14cd09eb9eb4bc3e6db378c1dc221ec70c4c9117c7ed4fa8db2',
    'ff39adeca1e8d6cf0193ac41d620223f0ad0545f9fe12f35ee87788c61dde3e0'
  ];
  receipt_count constant integer := 230;
  present_count bigint;
  empty_anywhere_count bigint;
  missing_count bigint;
  missing_sample text;
  conflict_count bigint;
  conflict_sample text;
  conflict_region text;
  extra_count bigint;
  extra_sample text;
  pending_count bigint;
  already_count bigint;
  updated_count bigint;
  final_count bigint;
begin
  if array_length(receipt, 1) is distinct from receipt_count then
    raise exception 'region repair receipt is corrupt: expected % ids, found %',
      receipt_count, coalesce(array_length(receipt, 1), 0)
      using errcode = '23514';
  end if;
  if (select count(distinct unnested.id)
        from unnest(receipt) as unnested(id)) <> receipt_count then
    raise exception 'region repair receipt is corrupt: duplicate ids present'
      using errcode = '23514';
  end if;

  select count(*)
    into present_count
    from public.curvy_roads road
   where road.id = any(receipt);

  select count(*)
    into empty_anywhere_count
    from public.curvy_roads road
   where coalesce(road.region, '') = '';

  if present_count = 0 and empty_anywhere_count = 0 then
    raise notice
      'region repair 20260716040000: fresh database, no receipt row and no empty region; no-op';
    return;
  end if;

  select count(*), min(unnested.id)
    into missing_count, missing_sample
    from unnest(receipt) as unnested(id)
   where not exists (
     select 1 from public.curvy_roads road where road.id = unnested.id
   );
  if missing_count > 0 then
    raise exception
      'region repair receipt row missing from curvy_roads: % of % absent (e.g. %)',
      missing_count, receipt_count, missing_sample
      using errcode = '23514';
  end if;

  select count(*), min(road.id), min(coalesce(road.region, '<null>'))
    into conflict_count, conflict_sample, conflict_region
    from public.curvy_roads road
   where road.id = any(receipt)
     and road.region is distinct from ''
     and road.region is distinct from repaired_region;
  if conflict_count > 0 then
    raise exception
      'region repair receipt row % holds unexpected region % (% conflicting rows); refusing to overwrite',
      conflict_sample, conflict_region, conflict_count
      using errcode = '23514';
  end if;

  select count(*), min(road.id)
    into extra_count, extra_sample
    from public.curvy_roads road
   where coalesce(road.region, '') = ''
     and not (road.id = any(receipt));
  if extra_count > 0 then
    raise exception
      'unexpected empty-region curvy_roads rows outside the repair receipt: % rows (e.g. %); snapshot has drifted',
      extra_count, extra_sample
      using errcode = '23514';
  end if;

  select count(*) filter (where road.region = ''),
         count(*) filter (where road.region = repaired_region)
    into pending_count, already_count
    from public.curvy_roads road
   where road.id = any(receipt);
  if pending_count + already_count <> receipt_count then
    raise exception
      'region repair state accounting failed: pending % + repaired % <> %',
      pending_count, already_count, receipt_count
      using errcode = '23514';
  end if;

  if pending_count = 0 then
    raise notice
      'region repair 20260716040000: all % receipt rows already %; idempotent no-op',
      receipt_count, repaired_region;
    return;
  end if;

  update public.curvy_roads road
     set region = repaired_region
   where road.id = any(receipt)
     and road.region = '';
  get diagnostics updated_count = row_count;
  if updated_count <> pending_count then
    raise exception
      'region repair updated % rows but expected %; aborting',
      updated_count, pending_count
      using errcode = '23514';
  end if;

  select count(*)
    into final_count
    from public.curvy_roads road
   where road.id = any(receipt)
     and road.region = repaired_region;
  if final_count <> receipt_count then
    raise exception
      'region repair post-check failed: % of % receipt rows repaired',
      final_count, receipt_count
      using errcode = '23514';
  end if;

  raise notice
    'region repair 20260716040000: updated % rows (of % receipt rows) to %',
    updated_count, receipt_count, repaired_region;
end;
$$;
