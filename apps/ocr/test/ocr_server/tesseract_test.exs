defmodule OcrServer.TesseractTest do
  use ExUnit.Case, async: true
  alias OcrServer.Tesseract
  # doctest OcrServer.Tesseract

  @png_with_world_text "iVBORw0KGgoAAAANSUhEUgAAAFIAAAAyCAIAAABAuhuWAAADnElEQVRoge2abWxTVRjH/+d23NCV
rXejve3s1m6xg+6tAg2pAyoD9wJuKhAWIAYzIiTgBzGQLDGGGE3U6BcTTIxBAxGMmKBmCIkGx5YF
xPHiHASYbuvVtuu63ttuK1uFatj1Qw1xBNcl0PXDOb+P957/8zy/nJPz5V7C8zzoIwuAKIqZHmNO
kWWZy/QMmYFp0wTTpgmmTRNMmyaYNk0wbZpg2jTBtGmCadNE5rV1wkJeq5vjpllpqUrIjveO5pkL
AUwo4U/2b51hbfmqeof76WMHdqZlkv8hPdqqeqR1OwDnmmfdTS+kpcXDkflDnhGyQEjjywempqa+
+/jt/75YsanF4nCeeGcfgApPQ7lnnbnEMTkWudpxsuf7r5JrltRuWPvi3lg49MVbe1Y17ypxunVC
3gctdYA6c1e7y+Nav1m0lQ4P3hgbHkqT2wxwUFUl4BVMjwEoKlu672jn8qZtAPSiJRrwAbBWuOpf
au2/2HVob/OFb454mndVeBqS4d72ts9e25FjEJ/Z/TrhuM7PD/5153ZKZ8Fsee6VN0ek/kOvbvnx
xOFCxxNpdnwAHADF59UbCgCYSkoVvyRa7QARTJZIwAugqqbRd/3S1bNtiT8nf+vuGLhyrrKmcVoJ
jWbefO2ZT99XApL/Rk/KlhUr6+Ox0a7jHyXiEyNSX99PP6RHbSY4AHLAm50raObx5pKyX7vbjUV2
EOiNZiUggRDRVqr4pHsB2TcgGC3Ti6gXvj4MYDwcPPXhG6k6EqP18UhQgpriUKQVDkB8PJq4PWmw
2MRie//lLr3RNH9BbnaOEBmSAEzdvXt/hpt+EaoYGwnOviUhXGad8e9NriLsGzQVL9bmCDE5FA0N
OdxrYnLo78QdqLilDBusxfcCoq1U9vfPtvwD9NTRkWC+yfYIZn8IkvumRvzeRdVrlYAXqhoN/r7I
XRMdTh5stbf9pK3S7axp4rW6shW1dtfKS6e/nGX1cSWk1ev1YgEAnbAw+bD3bFt2Xv6Tz28HkF9g
Lauue+RWKdFoNBqdTrdAMCyt2yT1dv9x7WKeubDSs37g8rlA3y8AxsPBiVF5WcPmp7buLq5a3nHs
4ODP55PhJbUbNu5/F4S41jUXOpw3z5+5r3pMCeUX2Op3tlZvbMnOFZLBRHzilhJavW1P1erGovJl
/ps9gmi51vntnDnH43HC8zz7vk0LTJsmmDZNMG2aYNo0wbRpgmnTBNOmCULnb/T/AKHkK1n8YOoX
AAAAAElFTkSuQmCC" |> String.replace("\n", "")

  @jpg_with_world_text "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAYEBQYFBAYGBQYHBwYIChAKCgkJChQODwwQFxQYGBcU
FhYaHSUfGhsjHBYWICwgIyYnKSopGR8tMC0oMCUoKSj/2wBDAQcHBwoIChMKChMoGhYaKCgoKCgo
KCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCj/wAARCAAhADwDAREA
AhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQA
AAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3
ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWm
p6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEA
AwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSEx
BhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElK
U1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3
uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD50hij
MSEopO0dqAHeVH/zzT8hQAeVH/zzT8hQAeVH/wA80/IUAHlR/wDPNPyFAB5Uf/PNPyFAB5Uf/PNP
yFAFK+VVlAUADb2FAHS6b4e1C+sbCWyRJ/tKSFUV8FfLA3ZzgdCMc85q1TbSsZupFNp9CeLw3dMA
8txawQC2jupJpGbbErnCg4UksfQA0/ZsHVQsfhq5bXrXSmubVJLtUa3mLMYpQ33cEKTz05AweuKP
Zvm5Q9quVy7CX2kvoLWlxeiwvQ7yRvbCRzsdAuVcqV5G8fdbqDSceSzeoKfPdLQXxbYw2/iSS106
3EUbJCyQoWbDPEjEDcSerHqadRJSsgpybjdl+Tw5FYaNrzXc9ncX1mIl2QyMWgcyhWB4APBI43D8
ar2dk77oj2nNKNtmcpWJuZ+of65f93+poA7nwj4nt9H0OOGSKZ7qO4SaFlAKhC0TSA5OckQgYxjk
1tCooqxhUpOcr/11/wAyS58QabdXGq2rpdx6VdRW8ULqimWLyVCoSu7ByM5G7v1oc4u66f5Aqckk
+qv+Ilvr+nr4q0a8cXaadpSRJFiNWlkCMW5G4AZYnuce9CmudPogdOXI11ZzV/5BvJTaySywlsq8
qBGP1AZgPzNZO19DZXtqbWsavZ3Gp2erWbXAvk8gvBLEojUxoq5DhiWyVHVR1q5STaktzOMGk4vY
talrOkPba+bIX/n6qySBJY0CwkSB2XcGJYdcHA7celOcbO3UmMJXjfocpWJuZ+of65f93+poAuQf
6mP/AHR/KgCSgAoAKACgAoAKAM/UP9cv+7/U0AVaACgAoAKACgAoAKACgD//2Q=="
                       |> String.replace("\n", "")

  @webp_with_world_text "UklGRp4BAABXRUJQVlA4IJIBAACwCQCdASpCACsAPpFCm0mlo6KhJmqosBIJZwDPKmwIaBymVr4n
B9VTiRSxzIioF3sbfjLqUd5y/z4vG/xkxT9HhDX8RCzKN4ynrj0ItcsuwQWZfuQ8AAD+/bMdpwQa
K1GbGBA38LDn7jglstDbRu0rz2wXzZPUfV+mAqpSFvw9b3xY4kTYUgjVWc6b1VoZAcG7zWXcqNt6
p1BhiP0KJv+UD69Mxvrg2LhjbF3nBrahX/qW/XpjxtE06MdTLR2vn1ddOwkVfp1umK6fRPeBhefI
Jjx3OgafCGAgNg3cJdW9O/lKENUsz7wGWbPOTOWhNu4t+Eo/fgmS6Vl+76IIX1b9r4183KBxK/sj
0fqZI9rwfX3COS46c57pwqtw6rNCqjbzcJy1YlYAqC+/bo2Yx7ueE515dIX5bTNu74ROcV4WuoUv
1sTOclhp3rPZAmybzkZuDuDvT84p2K9zmuYW9rEOqgp/N2Cb9QXf1fhYNbdIWwgteivIDHqrOC+2
U+N2D7R3OiMsxJ80cEno0gDdtlJIAAA=" |> String.replace("\n", "")

  test "recognizes from png" do
    image = Base.decode64!(@png_with_world_text)
    result = Tesseract.ocr([image])
    {status, text} = result
    assert 0 === status
    assert "world" == String.trim(text)
  end

  test "recognizes from jpg" do
    image = Base.decode64!(@jpg_with_world_text)
    result = Tesseract.ocr([image])
    {status, text} = result
    assert 0 === status
    assert "world" == String.trim(text)
  end

  test "recognizes from webp" do
    image = Base.decode64!(@webp_with_world_text)
    result = Tesseract.ocr([image])
    {status, text} = result
    assert 0 === status
    assert "world" == String.trim(text)
  end
end
